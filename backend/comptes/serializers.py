from rest_framework import serializers

from noyau import stockage
from noyau.erreurs import ErreurMetier

from .models import CODES_SERVICES, Citoyen, Entreprise, Prestataire, Utilisateur


def _lien(serializer, chemin):
    if not chemin:
        return None
    return stockage.lien_signe(serializer.context.get("request"), chemin)


class UtilisateurSerializer(serializers.ModelSerializer):
    class Meta:
        model = Utilisateur
        fields = ["id", "telephone", "type_compte"]


class CitoyenSerializer(serializers.ModelSerializer):
    citoyen_id = serializers.UUIDField(source="utilisateur_id", read_only=True)
    photo_url = serializers.SerializerMethodField()

    class Meta:
        model = Citoyen
        fields = ["citoyen_id", "nom", "prenom", "email", "telephone", "photo_url"]
        # Le téléphone est l'identifiant de connexion : il ne se change pas ici.
        read_only_fields = ["telephone"]

    def get_photo_url(self, obj):
        return _lien(self, obj.photo)


class PrestataireSerializer(serializers.ModelSerializer):
    """Profil du prestataire lui-même."""

    id = serializers.UUIDField(source="utilisateur_id", read_only=True)
    photo_url = serializers.SerializerMethodField()
    abonnement_valide = serializers.BooleanField(read_only=True)
    profil_complet = serializers.BooleanField(read_only=True)
    identite_figee = serializers.BooleanField(read_only=True)

    class Meta:
        model = Prestataire
        fields = [
            "id", "nom", "prenom", "telephone", "services", "photo_url",
            "en_ligne", "latitude", "longitude",
            "abonnement_expire_le", "type_abonnement", "essai_utilise",
            "abonnement_valide", "identite_verifiee", "profil_complet", "identite_figee",
        ]
        # En ligne, abonnement et badge passent par des actions dédiées ou
        # par l'équipe WANDA, jamais par une modification directe.
        read_only_fields = [
            "telephone", "en_ligne", "abonnement_expire_le", "type_abonnement",
            "essai_utilise", "identite_verifiee",
        ]

    def get_photo_url(self, obj):
        return _lien(self, obj.photo_pro)

    def validate_services(self, valeur):
        if not isinstance(valeur, list) or any(s not in CODES_SERVICES for s in valeur):
            raise serializers.ValidationError("Services possibles : " + ", ".join(CODES_SERVICES))
        # Ordre stable et sans doublon.
        return [s for s in CODES_SERVICES if s in valeur]

    def validate(self, donnees):
        p = self.instance
        if p is not None and p.identite_figee:
            for champ in ("nom", "prenom"):
                if champ in donnees and donnees[champ] != getattr(p, champ):
                    raise ErreurMetier("IDENTITE_FIGEE")
            if "services" in donnees and not set(p.services) <= set(donnees["services"]):
                raise ErreurMetier("IDENTITE_FIGEE")
        return donnees


class PrestatairePublicSerializer(serializers.ModelSerializer):
    """Ce que voit un client : identité, services, position, note."""

    id = serializers.UUIDField(source="utilisateur_id", read_only=True)
    photo_url = serializers.SerializerMethodField()
    note_moyenne = serializers.SerializerMethodField()
    nb_avis = serializers.IntegerField(read_only=True, default=0)

    class Meta:
        model = Prestataire
        fields = [
            "id", "nom", "prenom", "telephone", "services", "photo_url",
            "latitude", "longitude", "identite_verifiee", "note_moyenne", "nb_avis",
        ]

    def get_photo_url(self, obj):
        return _lien(self, obj.photo_pro)

    def get_note_moyenne(self, obj):
        note = getattr(obj, "note_moyenne", None)
        return round(float(note), 1) if note is not None else None


class EntrepriseSerializer(serializers.ModelSerializer):
    id = serializers.UUIDField(source="utilisateur_id", read_only=True)
    logo_url = serializers.SerializerMethodField()

    class Meta:
        model = Entreprise
        fields = ["id", "nom_entreprise", "secteur_activite", "telephone", "logo_url"]
        read_only_fields = ["telephone"]

    def get_logo_url(self, obj):
        return _lien(self, obj.logo)


class EnvoiCodeSerializer(serializers.Serializer):
    telephone = serializers.CharField(max_length=30)


class ConnexionSerializer(serializers.Serializer):
    telephone = serializers.CharField(max_length=30)
    code = serializers.CharField(max_length=10)
    type_compte = serializers.ChoiceField(
        choices=Utilisateur.Type.choices, required=False, allow_blank=True
    )


class EnLigneSerializer(serializers.Serializer):
    en_ligne = serializers.BooleanField()
    latitude = serializers.FloatField(required=False, min_value=-90, max_value=90)
    longitude = serializers.FloatField(required=False, min_value=-180, max_value=180)


class AppareilSerializer(serializers.Serializer):
    fcm_token = serializers.CharField(max_length=255)
    plateforme = serializers.ChoiceField(
        choices=["android", "ios", "web"], default="android"
    )
