import base64
import json
import os
import urllib.error

from django.db import transaction
from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import generics, serializers, status
from rest_framework.parsers import MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from comptes.models import Entreprise
from comptes.permissions import EstCitoyen, EstEntreprise
from demandes.ia import MODELE_PAR_DEFAUT, appeler_groq
from noyau import stockage
from noyau.erreurs import ErreurMetier
from notifications.services import notifier

from .models import Signalement
from .secteurs import secteur_pour_type, types_du_secteur

# Avancement d'une mission par l'entreprise.
TRANSITIONS = {
    ("en_attente", "en_cours"),
    ("en_attente", "rejete"),
    ("en_cours", "resolu"),
    ("en_cours", "rejete"),
}


class SignalementSerializer(serializers.ModelSerializer):
    image_url = serializers.SerializerMethodField()

    class Meta:
        model = Signalement
        fields = [
            "id", "type_probleme", "image_url", "latitude", "longitude", "entreprise",
            "statut", "ia_validation_details", "cree_le", "modifie_le",
        ]

    def get_image_url(self, obj):
        return stockage.lien_signe(self.context.get("request"), obj.image) if obj.image else None


class NouveauSignalement(serializers.Serializer):
    type_probleme = serializers.CharField(max_length=100)
    latitude = serializers.FloatField(min_value=-90, max_value=90)
    longitude = serializers.FloatField(min_value=-180, max_value=180)
    ia_validation_details = serializers.CharField(max_length=500, required=False, allow_blank=True)


class Signalements(generics.ListAPIView):
    """GET : mes signalements (citoyen) ou les missions de mon entreprise
    (attribuées, ou du type de mon secteur s'ils n'ont pas d'entreprise).
    POST multipart (citoyen) : image + type_probleme + latitude + longitude."""

    serializer_class = SignalementSerializer
    parser_classes = [MultiPartParser]

    def get_queryset(self):
        u = self.request.user
        if hasattr(u, "entreprise"):
            types = types_du_secteur(u.entreprise.secteur_activite)
            return Signalement.objects.filter(
                Q(entreprise=u.entreprise) | Q(entreprise__isnull=True, type_probleme__in=types)
            )
        if hasattr(u, "citoyen"):
            return Signalement.objects.filter(citoyen=u.citoyen)
        return Signalement.objects.none()

    def post(self, request):
        if not EstCitoyen().has_permission(request, self):
            raise ErreurMetier("NON_AUTORISE", status_code=403)
        s = NouveauSignalement(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        image = stockage.enregistrer(request.FILES.get("image"), "signalements", request.user.pk, "signalement")
        secteur = secteur_pour_type(d["type_probleme"])
        entreprise = Entreprise.objects.filter(secteur_activite=secteur).first()
        with transaction.atomic():
            sig = Signalement.objects.create(
                type_probleme=d["type_probleme"].strip(),
                image=image,
                latitude=d["latitude"],
                longitude=d["longitude"],
                entreprise=entreprise,
                citoyen=request.user.citoyen,
                ia_validation_details=d.get("ia_validation_details", ""),
            )
            if entreprise is not None:
                notifier(entreprise.utilisateur, "Nouveau signalement",
                         "{} signalé près de vous.".format(sig.type_probleme), signalement=sig.pk)
        return Response(
            SignalementSerializer(sig, context={"request": request}).data,
            status=status.HTTP_201_CREATED,
        )


class AvancerSignalement(APIView):
    """POST {statut} (entreprise) : en_cours, resolu ou rejete."""

    permission_classes = [EstEntreprise]

    def post(self, request, pk):
        e = request.user.entreprise
        types = types_du_secteur(e.secteur_activite)
        sig = get_object_or_404(
            Signalement.objects.filter(
                Q(entreprise=e) | Q(entreprise__isnull=True, type_probleme__in=types)
            ),
            pk=pk,
        )
        nouveau = request.data.get("statut")
        if (sig.statut, nouveau) not in TRANSITIONS:
            raise ErreurMetier("TRANSITION_INTERDITE", status_code=409)
        sig.statut = nouveau
        sig.entreprise = e
        sig.save(update_fields=["statut", "entreprise", "modifie_le"])
        if sig.citoyen_id:
            notifier(
                sig.citoyen.utilisateur,
                "Signalement : " + sig.type_probleme,
                {
                    "en_cours": "Une entreprise a pris en charge votre signalement.",
                    "resolu": "Le problème signalé est résolu. Merci !",
                    "rejete": "Votre signalement n'a pas pu être retenu.",
                }[nouveau],
                signalement=sig.pk,
            )
        return Response(SignalementSerializer(sig, context={"request": request}).data)


class AnalyserSignalement(APIView):
    """POST multipart (image + categorie) : l'IA vérifie que la photo est
    réelle et, pour « Autre (IA) », identifie le problème.
    Réponse : {valid, detected_type, reason} ; sans IA : valid = null."""

    permission_classes = [EstCitoyen]
    parser_classes = [MultiPartParser]

    def post(self, request):
        categorie = (request.data.get("categorie") or "").strip()
        image = request.FILES.get("image")
        if not categorie or image is None or image.size > 4 * 1024 * 1024:
            raise ErreurMetier("FICHIER_INVALIDE")
        cle = os.environ.get("GROQ_API_KEY")
        if not cle:
            return Response({"valid": None, "detected_type": None, "reason": "IA indisponible"})
        consigne = (
            "Analyse cette image de signalement citoyen.\nCatégorie choisie : {}.\n"
            "Instructions :\n1. Vérifie si l'image est une photo réelle de terrain.\n"
            "2. Si 'Autre (IA)', identifie précisément le problème.\n"
            '3. Réponds uniquement en JSON : {{"valid": bool, "detected_type": "string", '
            '"reason": "string"}}'
        ).format(categorie)
        modele = os.environ.get("GROQ_VISION_MODEL") or MODELE_PAR_DEFAUT
        try:
            contenu = appeler_groq(cle, modele, consigne, [base64.b64encode(image.read()).decode()])
            brut = json.loads(contenu)
        except (urllib.error.URLError, OSError, KeyError, IndexError, ValueError):
            return Response({"valid": None, "detected_type": None, "reason": "IA indisponible"})
        return Response(
            {
                "valid": brut.get("valid") if isinstance(brut.get("valid"), bool) else None,
                "detected_type": str(brut.get("detected_type") or "")[:100] or None,
                "reason": str(brut.get("reason") or "")[:300] or None,
            }
        )
