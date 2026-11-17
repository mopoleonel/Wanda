from django.db import transaction
from django.db.models import Avg, Count
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import generics, status
from rest_framework.parsers import MultiPartParser
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken

from noyau import stockage
from noyau.erreurs import ErreurMetier
from noyau.telephone import normaliser

from . import otp
from .limites import CodeParIP, CodeParNumero, VerificationParNumero
from .models import DUREE_ESSAI, AppareilPush, Citoyen, Entreprise, Prestataire, Utilisateur
from .permissions import EstCitoyen, EstEntreprise, EstPrestataire
from .serializers import (
    AppareilSerializer,
    CitoyenSerializer,
    ConnexionSerializer,
    EnLigneSerializer,
    EntrepriseSerializer,
    EnvoiCodeSerializer,
    PrestatairePublicSerializer,
    PrestataireSerializer,
    UtilisateurSerializer,
)


def _telephone(saisie):
    telephone = normaliser(saisie)
    if telephone is None:
        raise ErreurMetier("TELEPHONE_INVALIDE")
    return telephone


def profil_de(utilisateur, request):
    """Profil sérialisé selon le type de compte (None s'il n'existe pas)."""
    contexte = {"request": request}
    if hasattr(utilisateur, "citoyen"):
        return CitoyenSerializer(utilisateur.citoyen, context=contexte).data
    if hasattr(utilisateur, "prestataire"):
        return PrestataireSerializer(utilisateur.prestataire, context=contexte).data
    if hasattr(utilisateur, "entreprise"):
        return EntrepriseSerializer(utilisateur.entreprise, context=contexte).data
    return None


# --------------------------------------------------------------- connexion


class EnvoyerCode(APIView):
    """POST {telephone} : envoie un code de connexion par WhatsApp."""

    permission_classes = [AllowAny]
    throttle_classes = [CodeParNumero, CodeParIP]

    def post(self, request):
        s = EnvoiCodeSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        telephone = _telephone(s.validated_data["telephone"])
        otp.envoyer_code(telephone)
        return Response({"telephone": telephone, "expire_dans": 300})


class Connexion(APIView):
    """POST {telephone, code, type_compte?} : vérifie le code et renvoie les
    jetons. Le compte est créé au premier passage, avec son profil vide
    (type_compte obligatoire dans ce cas, sauf pour une entreprise qui
    complète ensuite PUT /api/moi/entreprise)."""

    permission_classes = [AllowAny]
    throttle_classes = [VerificationParNumero, CodeParIP]

    def post(self, request):
        s = ConnexionSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        telephone = _telephone(s.validated_data["telephone"])
        type_demande = s.validated_data.get("type_compte") or ""
        otp.verifier_code(telephone, s.validated_data["code"])

        with transaction.atomic():
            utilisateur, nouveau = Utilisateur.objects.get_or_create(telephone=telephone)
            if type_demande:
                if not utilisateur.type_compte:
                    utilisateur.type_compte = type_demande
                    utilisateur.save(update_fields=["type_compte"])
                elif utilisateur.type_compte != type_demande:
                    raise ErreurMetier("TYPE_COMPTE_FIGE", status_code=409)
            if utilisateur.type_compte == Utilisateur.Type.CITOYEN:
                Citoyen.objects.get_or_create(utilisateur=utilisateur, defaults={"telephone": telephone})
            elif utilisateur.type_compte == Utilisateur.Type.PARTICULIER:
                Prestataire.objects.get_or_create(utilisateur=utilisateur, defaults={"telephone": telephone})

        jeton = RefreshToken.for_user(utilisateur)
        return Response(
            {
                "acces": str(jeton.access_token),
                "rafraichissement": str(jeton),
                "nouveau": nouveau,
                "utilisateur": UtilisateurSerializer(utilisateur).data,
                "profil": profil_de(utilisateur, request),
            }
        )


class Moi(APIView):
    """GET : l'utilisateur connecté et son profil."""

    def get(self, request):
        return Response(
            {
                "utilisateur": UtilisateurSerializer(request.user).data,
                "profil": profil_de(request.user, request),
            }
        )


# --------------------------------------------------------------- profils


class MonProfilCitoyen(generics.RetrieveUpdateAPIView):
    serializer_class = CitoyenSerializer
    permission_classes = [EstCitoyen]
    http_method_names = ["get", "patch"]

    def get_object(self):
        return self.request.user.citoyen


class MonProfilPrestataire(generics.RetrieveUpdateAPIView):
    serializer_class = PrestataireSerializer
    permission_classes = [EstPrestataire]
    http_method_names = ["get", "patch"]

    def get_object(self):
        return Prestataire.objects.get(pk=self.request.user.pk)


class MonEntreprise(APIView):
    """GET ; PUT crée ou complète la fiche (nom, secteur) ; PATCH modifie."""

    def get(self, request):
        e = get_object_or_404(Entreprise, utilisateur=request.user)
        return Response(EntrepriseSerializer(e, context={"request": request}).data)

    def put(self, request):
        u = request.user
        if u.type_compte not in ("", Utilisateur.Type.ENTREPRISE):
            raise ErreurMetier("TYPE_COMPTE_FIGE", status_code=409)
        instance = Entreprise.objects.filter(utilisateur=u).first()
        s = EntrepriseSerializer(instance, data=request.data, context={"request": request})
        s.is_valid(raise_exception=True)
        with transaction.atomic():
            if not u.type_compte:
                u.type_compte = Utilisateur.Type.ENTREPRISE
                u.save(update_fields=["type_compte"])
            s.save(utilisateur=u, telephone=u.telephone)
        return Response(s.data, status=status.HTTP_200_OK if instance else status.HTTP_201_CREATED)

    def patch(self, request):
        e = get_object_or_404(Entreprise, utilisateur=request.user)
        s = EntrepriseSerializer(e, data=request.data, partial=True, context={"request": request})
        s.is_valid(raise_exception=True)
        s.save()
        return Response(s.data)


class MaPhoto(APIView):
    """POST multipart « fichier » : photo du profil (citoyen), photo
    professionnelle (prestataire) ou logo (entreprise)."""

    parser_classes = [MultiPartParser]

    def post(self, request):
        u = request.user
        if hasattr(u, "citoyen"):
            profil, champ = u.citoyen, "photo"
        elif hasattr(u, "prestataire"):
            profil, champ = u.prestataire, "photo_pro"
        elif hasattr(u, "entreprise"):
            profil, champ = u.entreprise, "logo"
        else:
            raise ErreurMetier("NON_AUTORISE", status_code=403)
        chemin = stockage.enregistrer(request.FILES.get("fichier"), "profils", u.pk, "profil")
        setattr(profil, champ, chemin)
        profil.save(update_fields=[champ])
        return Response(profil_de(u, request))


class EnLigne(APIView):
    """POST {en_ligne, latitude?, longitude?} : visibilité du prestataire."""

    permission_classes = [EstPrestataire]

    def post(self, request):
        s = EnLigneSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        p = Prestataire.objects.get(pk=request.user.pk)
        en_ligne = s.validated_data["en_ligne"]
        if en_ligne and not p.abonnement_valide:
            raise ErreurMetier("ABONNEMENT_REQUIS")
        if en_ligne and not p.services:
            raise ErreurMetier("PROFIL_INCOMPLET")
        p.en_ligne = en_ligne
        champs = ["en_ligne"]
        for c in ("latitude", "longitude"):
            if c in s.validated_data:
                setattr(p, c, s.validated_data[c])
                champs.append(c)
        p.save(update_fields=champs)
        return Response(PrestataireSerializer(p, context={"request": request}).data)


class EssaiGratuit(APIView):
    """POST : active l'essai gratuit de 14 jours (une seule fois)."""

    permission_classes = [EstPrestataire]

    def post(self, request):
        with transaction.atomic():
            p = Prestataire.objects.select_for_update().get(pk=request.user.pk)
            if p.essai_utilise:
                raise ErreurMetier("ESSAI_DEJA_UTILISE")
            p.essai_utilise = True
            p.type_abonnement = "ESSAI"
            p.abonnement_expire_le = timezone.now() + DUREE_ESSAI
            p.save(update_fields=["essai_utilise", "type_abonnement", "abonnement_expire_le"])
        return Response(PrestataireSerializer(p, context={"request": request}).data)


class Appareils(APIView):
    """POST {fcm_token, plateforme} : enregistre l'appareil pour les
    notifications. Un jeton déjà connu passe au compte connecté."""

    def post(self, request):
        s = AppareilSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        AppareilPush.objects.update_or_create(
            fcm_token=s.validated_data["fcm_token"],
            defaults={"utilisateur": request.user, "plateforme": s.validated_data["plateforme"]},
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


class Appareil(APIView):
    def delete(self, request, jeton):
        AppareilPush.objects.filter(utilisateur=request.user, fcm_token=jeton).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


# ------------------------------------------------- prestataires (clients)


def prestataires_visibles(service=None):
    """En ligne, avec un abonnement valide et au moins un service (celui
    demandé s'il est précisé) ; note moyenne et nombre d'avis calculés par la
    base. Les services sont filtrés en Python : le SQLite de développement ne
    sait pas chercher dans un champ JSON."""
    qs = (
        Prestataire.objects.filter(en_ligne=True, abonnement_expire_le__gt=timezone.now())
        .annotate(note_moyenne=Avg("avis_recus__note"), nb_avis=Count("avis_recus"))
        .order_by("-identite_verifiee", "nom")
    )
    return [p for p in qs if p.services and (service is None or service in p.services)]


class PrestatairesDisponibles(generics.ListAPIView):
    """GET ?service=menage : prestataires en ligne (tous services sinon)."""

    serializer_class = PrestatairePublicSerializer
    pagination_class = None

    def get_queryset(self):
        return prestataires_visibles(self.request.query_params.get("service") or None)


class PrestataireDetail(generics.RetrieveAPIView):
    serializer_class = PrestatairePublicSerializer

    def get_queryset(self):
        return Prestataire.objects.annotate(
            note_moyenne=Avg("avis_recus__note"), nb_avis=Count("avis_recus")
        )
