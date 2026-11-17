from rest_framework import serializers
from rest_framework.response import Response
from rest_framework.views import APIView

from noyau.erreurs import ErreurMetier

from . import calcul
from .models import prix_demande, tarifs_actuels


class DemandePrix(serializers.Serializer):
    service = serializers.ChoiceField(choices=calcul.SERVICES)
    formule = serializers.ChoiceField(choices=calcul.FORMULES)
    frequence = serializers.ChoiceField(
        choices=calcul.FREQUENCES, required=False, allow_null=True
    )
    reponses = serializers.DictField(required=False, default=dict)
    produits = serializers.BooleanField(required=False, default=False)

    def validate(self, d):
        if d["formule"] == "abonnement" and not d.get("frequence"):
            raise ErreurMetier("FORMULE_INVALIDE")
        if d["formule"] == "ponctuelle":
            d["frequence"] = None
        return d


class Tarifs(APIView):
    """GET : tous les paramètres, pour l'estimation en direct dans l'app."""

    def get(self, request):
        return Response(tarifs_actuels())


class Prix(APIView):
    """POST {service, formule, frequence, reponses, produits} : prix calculé
    par le serveur (celui qui sera enregistré à la réservation)."""

    def post(self, request):
        s = DemandePrix(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        return Response(
            prix_demande(d["service"], d["formule"], d["frequence"], d["reponses"], d["produits"])
        )
