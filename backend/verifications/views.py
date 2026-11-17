from rest_framework import serializers, status
from rest_framework.parsers import MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from comptes.permissions import EstPrestataire

from . import services
from .models import Verification


class DepotSerializer(serializers.Serializer):
    nom = serializers.CharField(max_length=100)
    prenoms = serializers.CharField(max_length=150)
    numero_document = serializers.CharField(max_length=50, required=False, allow_blank=True)
    date_naissance = serializers.DateField(required=False, allow_null=True)
    lieu_naissance = serializers.CharField(max_length=100, required=False, allow_blank=True)
    sexe = serializers.ChoiceField(choices=["M", "F"], required=False, allow_blank=True)
    date_expiration = serializers.DateField(required=False, allow_null=True)
    mrz_presente = serializers.BooleanField(required=False, default=False)
    mrz_valide = serializers.BooleanField(required=False, default=False)
    saisie_corrigee = serializers.BooleanField(required=False, default=False)
    consentement = serializers.BooleanField()
    consentement_version = serializers.CharField(max_length=20)
    consentement_texte = serializers.CharField()


class VerificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Verification
        fields = ["id", "statut", "motif_rejet", "cree_le", "verifie_le"]


class Certification(APIView):
    """GET : dernière demande de certification et son statut.
    POST multipart (recto, verso, selfie + identité lue + consentement)."""

    permission_classes = [EstPrestataire]
    parser_classes = [MultiPartParser]

    def get(self, request):
        v = request.user.prestataire.verifications.first()
        return Response(VerificationSerializer(v).data if v else None)

    def post(self, request):
        s = DepotSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        v = services.deposer(request.user.prestataire, request.FILES, s.validated_data)
        return Response(VerificationSerializer(v).data, status=status.HTTP_201_CREATED)
