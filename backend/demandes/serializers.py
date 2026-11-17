from rest_framework import serializers

from noyau import stockage
from tarification import calcul

from .models import Ajustement, Avis, Demande, numero_fiche


def _liens(serializer, chemins):
    requete = serializer.context.get("request")
    return [stockage.lien_signe(requete, c) for c in (chemins or [])]


class AjustementSerializer(serializers.ModelSerializer):
    demande = serializers.UUIDField(source="demande_id", read_only=True)
    photos_liens = serializers.SerializerMethodField()

    class Meta:
        model = Ajustement
        fields = [
            "id", "demande", "minutes_supp", "produits_supp", "motif", "photos",
            "photos_liens", "prix_supp", "statut", "cree_le", "repondu_le",
        ]

    def get_photos_liens(self, obj):
        return _liens(self, obj.photos)


class DemandeSerializer(serializers.ModelSerializer):
    """Une demande, vue par le client ou par le prestataire."""

    numero = serializers.SerializerMethodField()
    photos_liens = serializers.SerializerMethodField()
    prestataire = serializers.SerializerMethodField()
    client = serializers.SerializerMethodField()
    ajustement_en_attente = serializers.SerializerMethodField()
    nb_passages = serializers.SerializerMethodField()
    note = serializers.SerializerMethodField()

    class Meta:
        model = Demande
        fields = [
            "id", "numero", "statut", "date_sollicitation", "date_fin", "modifie_le",
            "service", "formule", "frequence", "reponses", "produits_fournis",
            "minutes_estimees", "prix_passage", "prix_total", "prix_detail",
            "photos", "photos_liens", "ia_analyse", "date_souhaitee", "creneau",
            "motif_refus", "prestataire", "client", "ajustement_en_attente",
            "nb_passages", "note",
        ]

    def get_numero(self, obj):
        return numero_fiche(obj.pk)

    def get_photos_liens(self, obj):
        return _liens(self, obj.photos)

    def get_prestataire(self, obj):
        p = obj.prestataire
        return {
            "id": str(p.pk),
            "nom": p.nom,
            "prenom": p.prenom,
            "telephone": p.telephone,
            "services": p.services,
            "identite_verifiee": p.identite_verifiee,
            "photo_url": stockage.lien_signe(self.context.get("request"), p.photo_pro)
            if p.photo_pro else None,
        }

    def get_client(self, obj):
        return {
            "id": str(obj.citoyen_id),
            "nom": obj.nom_citoyen,
            "prenom": obj.prenom_citoyen,
            "telephone": obj.numero_citoyen,
        }

    def get_ajustement_en_attente(self, obj):
        for a in obj.ajustements.all():
            if a.statut == "en_attente":
                return AjustementSerializer(a, context=self.context).data
        return None

    def get_nb_passages(self, obj):
        return len(obj.passages.all()) if obj.formule == "abonnement" else None

    def get_note(self, obj):
        avis = getattr(obj, "avis", None)
        return avis.note if avis else None


class CreationDemandeSerializer(serializers.Serializer):
    prestataire = serializers.UUIDField()
    service = serializers.ChoiceField(choices=calcul.SERVICES)
    formule = serializers.ChoiceField(choices=calcul.FORMULES)
    frequence = serializers.ChoiceField(
        choices=calcul.FREQUENCES, required=False, allow_null=True, allow_blank=True
    )
    reponses = serializers.DictField(required=False, default=dict)
    produits = serializers.BooleanField(required=False, default=False)
    photos = serializers.ListField(child=serializers.CharField(max_length=255), max_length=3)
    analyse = serializers.UUIDField(required=False, allow_null=True)
    date_souhaitee = serializers.DateField()
    creneau = serializers.ChoiceField(choices=Demande.Creneau.choices)


class RefusSerializer(serializers.Serializer):
    motif = serializers.CharField(required=False, allow_blank=True, max_length=200)


class DemandeAjustementSerializer(serializers.Serializer):
    minutes = serializers.IntegerField(required=False, default=0, min_value=0, max_value=600)
    produits = serializers.IntegerField(required=False, default=0, min_value=0, max_value=100000)
    motif = serializers.CharField(max_length=500)
    photos = serializers.ListField(
        child=serializers.CharField(max_length=255), required=False, default=list, max_length=3
    )


class ReponseAjustementSerializer(serializers.Serializer):
    accepte = serializers.BooleanField()


class NoteSerializer(serializers.Serializer):
    note = serializers.IntegerField(min_value=1, max_value=5)
    commentaire = serializers.CharField(required=False, allow_blank=True, max_length=500)


class AvisSerializer(serializers.ModelSerializer):
    client = serializers.SerializerMethodField()

    class Meta:
        model = Avis
        fields = ["id", "demande", "prestataire", "note", "commentaire", "client", "cree_le"]

    def get_client(self, obj):
        # Prénom seulement : un avis public ne révèle pas l'identité complète.
        return obj.citoyen.prenom or "Client WANDA"


class AnalyseSerializer(serializers.Serializer):
    service = serializers.ChoiceField(choices=calcul.SERVICES)
    reponses = serializers.DictField(required=False, default=dict)
    photos = serializers.ListField(
        child=serializers.CharField(max_length=255), min_length=1, max_length=3
    )
