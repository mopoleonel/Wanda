import uuid

from django.db.models import Avg, Count, Prefetch
from django.http import Http404
from django.shortcuts import get_object_or_404
from django.utils.dateparse import parse_datetime
from rest_framework import generics, status
from rest_framework.parsers import MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from comptes.permissions import EstCitoyen
from noyau import stockage
from noyau.erreurs import ErreurMetier, NonAutorise

from . import ia, services
from .models import Ajustement, Avis, Demande
from .serializers import (
    AjustementSerializer,
    AnalyseSerializer,
    AvisSerializer,
    CreationDemandeSerializer,
    DemandeAjustementSerializer,
    DemandeSerializer,
    NoteSerializer,
    RefusSerializer,
    ReponseAjustementSerializer,
)


def demandes_avec_details():
    return Demande.objects.select_related("prestataire", "avis").prefetch_related(
        Prefetch("ajustements", queryset=Ajustement.objects.order_by("-cree_le")),
        "passages",
    )


def demande_de(utilisateur, pk):
    """La demande, seulement si l'utilisateur en est le client ou le
    prestataire (sinon : introuvable, sans dire qu'elle existe)."""
    demande = get_object_or_404(demandes_avec_details(), pk=pk)
    if utilisateur.pk not in (demande.citoyen_id, demande.prestataire_id):
        raise Http404
    return demande


class MesDemandes(generics.ListCreateAPIView):
    """GET : mes demandes (client) ou mes missions (prestataire).
         ?role=citoyen|prestataire  ?statut=en_attente,accepte
         ?depuis=<date ISO> : seulement celles modifiées depuis (suivi en
         direct par interrogation régulière). Bornes incluses : une fiche
         peut revenir deux fois, jamais être manquée (horloges grossières).
    POST : réserver (client) ; le prix est calculé par le serveur."""

    serializer_class = DemandeSerializer

    def get_queryset(self):
        u = self.request.user
        role = self.request.query_params.get("role")
        if role is None:
            role = "citoyen" if hasattr(u, "citoyen") else "prestataire"
        qs = demandes_avec_details()
        qs = qs.filter(citoyen_id=u.pk) if role == "citoyen" else qs.filter(prestataire_id=u.pk)
        statuts = self.request.query_params.get("statut")
        if statuts:
            qs = qs.filter(statut__in=statuts.split(","))
        depuis = parse_datetime(self.request.query_params.get("depuis") or "")
        if depuis is not None:
            qs = qs.filter(modifie_le__gte=depuis)
        return qs

    def create(self, request, *args, **kwargs):
        if not hasattr(request.user, "citoyen"):
            raise ErreurMetier("CITOYEN_INCONNU")
        s = CreationDemandeSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        demande = services.creer_demande(
            request.user,
            prestataire_id=d["prestataire"],
            service=d["service"],
            formule=d["formule"],
            frequence=d.get("frequence") or "",
            reponses=d["reponses"],
            produits=d["produits"],
            photos=d["photos"],
            analyse_id=d.get("analyse"),
            date=d["date_souhaitee"],
            creneau=d["creneau"],
        )
        donnees = DemandeSerializer(
            demande_de(request.user, demande.pk), context={"request": request}
        ).data
        return Response(donnees, status=status.HTTP_201_CREATED)


class DemandeDetail(APIView):
    def get(self, request, pk):
        return Response(
            DemandeSerializer(demande_de(request.user, pk), context={"request": request}).data
        )


class ChangerStatut(APIView):
    """POST /demandes/<id>/<action> : accepter, refuser {motif}, terminer
    (prestataire) ; annuler, classer (client)."""

    ACTIONS = {
        "accepter": "accepte",
        "refuser": "refuse",
        "terminer": "termine",
        "annuler": "annule",
        "classer": "archive",
    }

    def post(self, request, pk, action):
        nouveau = self.ACTIONS.get(action)
        if nouveau is None:
            raise Http404
        motif = ""
        if nouveau == "refuse":
            s = RefusSerializer(data=request.data)
            s.is_valid(raise_exception=True)
            motif = s.validated_data.get("motif", "")
        services.changer_statut(pk, request.user, nouveau, motif)
        return Response(
            DemandeSerializer(demande_de(request.user, pk), context={"request": request}).data
        )


class Ajustements(APIView):
    """GET : ajustements d'une demande. POST (prestataire) : en demander un."""

    def get(self, request, pk):
        demande = demande_de(request.user, pk)
        return Response(
            AjustementSerializer(
                demande.ajustements.all(), many=True, context={"request": request}
            ).data
        )

    def post(self, request, pk):
        s = DemandeAjustementSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        a = services.demander_ajustement(
            pk, request.user, minutes=d["minutes"], produits=d["produits"],
            motif=d["motif"], photos=d["photos"],
        )
        return Response(
            AjustementSerializer(a, context={"request": request}).data,
            status=status.HTTP_201_CREATED,
        )


class RepondreAjustement(APIView):
    """POST {accepte} (client)."""

    def post(self, request, pk):
        s = ReponseAjustementSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        a = services.repondre_ajustement(pk, request.user, s.validated_data["accepte"])
        return Response(AjustementSerializer(a, context={"request": request}).data)


class Passages(APIView):
    """GET : passages pointés. POST (prestataire) : pointer celui du jour."""

    def get(self, request, pk):
        demande = demande_de(request.user, pk)
        return Response([p.effectue_le for p in demande.passages.all()])

    def post(self, request, pk):
        passage = services.pointer_passage(pk, request.user)
        return Response({"effectue_le": passage.effectue_le}, status=status.HTTP_201_CREATED)


class Noter(APIView):
    """POST {note, commentaire} (client, mission terminée)."""

    def post(self, request, pk):
        s = NoteSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        avis = services.noter(
            pk, request.user, s.validated_data["note"], s.validated_data.get("commentaire", "")
        )
        return Response(AvisSerializer(avis).data, status=status.HTTP_201_CREATED)


class Notes(APIView):
    """GET ?ids=a,b : note moyenne et nombre d'avis de plusieurs
    prestataires en une requête (liste des prestataires)."""

    def get(self, request):
        ids = []
        for brut in (request.query_params.get("ids") or "").split(",")[:200]:
            try:
                ids.append(uuid.UUID(brut.strip()))
            except ValueError:
                continue
        lignes = (
            Avis.objects.filter(prestataire_id__in=ids)
            .values("prestataire_id")
            .annotate(moyenne=Avg("note"), nombre=Count("id"))
        )
        return Response({
            str(l["prestataire_id"]): {"moyenne": round(float(l["moyenne"]), 2), "nombre": l["nombre"]}
            for l in lignes
        })


class AvisPrestataire(generics.ListAPIView):
    """GET : avis reçus par un prestataire."""

    serializer_class = AvisSerializer

    def get_queryset(self):
        return Avis.objects.select_related("citoyen").filter(prestataire_id=self.kwargs["pk"])


class EnvoyerPhoto(APIView):
    """POST multipart « fichier » (+ « dossier ») : photo d'une demande ou
    d'un ajustement. Renvoie son chemin, à joindre ensuite à la demande."""

    parser_classes = [MultiPartParser]

    def post(self, request):
        chemin = stockage.enregistrer(
            request.FILES.get("fichier"), "demandes", request.user.pk,
            request.data.get("dossier") or "demande",
        )
        return Response(
            {"chemin": chemin, "url": stockage.lien_signe(request, chemin)},
            status=status.HTTP_201_CREATED,
        )


class LienPhoto(APIView):
    """GET ?chemin=... : lien de courte durée, si l'utilisateur y a droit."""

    def get(self, request):
        chemin = request.query_params.get("chemin", "")
        if not services.peut_voir_photo(request.user, chemin):
            raise NonAutorise()
        return Response({"url": stockage.lien_signe(request, chemin)})


class Analyser(APIView):
    """POST {service, reponses, photos} (client) : analyse IA des photos.
    Répond toujours 200 : sans IA, resultat est null."""

    permission_classes = [EstCitoyen]

    def post(self, request):
        s = AnalyseSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        for chemin in d["photos"]:
            if not chemin.startswith("demandes/") or not stockage.appartient_a(
                chemin, request.user.pk
            ):
                raise ErreurMetier("PHOTO_INVALIDE", status_code=403)
        analyse = ia.analyser(request.user.citoyen, d["service"], d["reponses"], d["photos"])
        return Response(
            {"analyse_id": analyse.pk, "resultat": analyse.resultat, "erreur": analyse.erreur or None}
        )
