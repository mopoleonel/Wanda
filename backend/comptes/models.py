"""Comptes : un utilisateur = un numéro de téléphone (connexion par code).

Les identifiants sont des UUID, comme dans Supabase (auth.users) : un import
des données existantes garde les mêmes identifiants (voir README).

Un utilisateur a un type de compte et le profil correspondant :
  citoyen      -> Citoyen      (table « citoyens » de Supabase)
  particulier  -> Prestataire  (table « particuliers »)
  entreprise   -> Entreprise   (table « entreprises »)
"""
import uuid
from datetime import timedelta

from django.contrib.auth.models import AbstractBaseUser, BaseUserManager, PermissionsMixin
from django.db import models
from django.utils import timezone

from noyau.champs import ChampJSON

SERVICES = (
    ("menage", "Ménage et nettoyage"),
    ("linge", "Linge"),
    ("dechets", "Ramassage des poubelles"),
    ("nuisibles", "Lutte contre les nuisibles"),
)
CODES_SERVICES = tuple(code for code, _ in SERVICES)

DUREE_ESSAI = timedelta(days=14)


class GestionnaireUtilisateurs(BaseUserManager):
    use_in_migrations = True

    def create_user(self, telephone, password=None, **champs):
        if not telephone:
            raise ValueError("Le téléphone est obligatoire.")
        utilisateur = self.model(telephone=telephone, **champs)
        if password:
            utilisateur.set_password(password)
        else:
            utilisateur.set_unusable_password()
        utilisateur.save(using=self._db)
        return utilisateur

    def create_superuser(self, telephone, password=None, **champs):
        champs.setdefault("is_staff", True)
        champs.setdefault("is_superuser", True)
        return self.create_user(telephone, password, **champs)


class Utilisateur(AbstractBaseUser, PermissionsMixin):
    class Type(models.TextChoices):
        CITOYEN = "citoyen", "Citoyen"
        PARTICULIER = "particulier", "Prestataire"
        ENTREPRISE = "entreprise", "Entreprise"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    telephone = models.CharField("téléphone", max_length=20, unique=True)
    type_compte = models.CharField(
        "type de compte", max_length=20, choices=Type.choices, blank=True
    )
    is_active = models.BooleanField("actif", default=True)
    is_staff = models.BooleanField("équipe WANDA", default=False)
    date_creation = models.DateTimeField("créé le", default=timezone.now)

    objects = GestionnaireUtilisateurs()

    USERNAME_FIELD = "telephone"

    class Meta:
        verbose_name = "utilisateur"

    def __str__(self):
        return self.telephone


class CodeConnexion(models.Model):
    """Code à 6 chiffres envoyé par WhatsApp. Seule son empreinte est gardée."""

    telephone = models.CharField(max_length=20, db_index=True)
    empreinte = models.CharField(max_length=128)
    expire_le = models.DateTimeField()
    essais = models.PositiveSmallIntegerField(default=0)
    utilise = models.BooleanField(default=False)
    cree_le = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "code de connexion"
        verbose_name_plural = "codes de connexion"
        ordering = ["-cree_le"]


class Citoyen(models.Model):
    utilisateur = models.OneToOneField(
        Utilisateur, on_delete=models.CASCADE, primary_key=True, related_name="citoyen"
    )
    nom = models.CharField(max_length=100, blank=True)
    prenom = models.CharField("prénom", max_length=100, blank=True)
    email = models.EmailField(blank=True)
    telephone = models.CharField("téléphone", max_length=20)
    photo = models.CharField(max_length=255, blank=True)

    class Meta:
        verbose_name = "citoyen"

    def __str__(self):
        return " ".join(p for p in (self.prenom, self.nom) if p) or self.telephone


class Prestataire(models.Model):
    """Artisan / prestataire de services ménagers (« particulier »)."""

    utilisateur = models.OneToOneField(
        Utilisateur, on_delete=models.CASCADE, primary_key=True, related_name="prestataire"
    )
    nom = models.CharField(max_length=100, blank=True)
    prenom = models.CharField("prénom", max_length=100, blank=True)
    telephone = models.CharField("téléphone", max_length=20)
    services = ChampJSON(default=list, blank=True)
    photo_pro = models.CharField("photo professionnelle", max_length=255, blank=True)
    en_ligne = models.BooleanField("en ligne", default=False)
    latitude = models.FloatField(null=True, blank=True)
    longitude = models.FloatField(null=True, blank=True)
    abonnement_expire_le = models.DateTimeField("abonnement jusqu'au", null=True, blank=True)
    type_abonnement = models.CharField(max_length=30, blank=True)
    essai_utilise = models.BooleanField("essai utilisé", default=False)
    identite_verifiee = models.BooleanField("identité vérifiée", default=False)

    class Meta:
        verbose_name = "prestataire"

    def __str__(self):
        return " ".join(p for p in (self.prenom, self.nom) if p) or self.telephone

    @property
    def abonnement_valide(self):
        return bool(self.abonnement_expire_le and self.abonnement_expire_le > timezone.now())

    @property
    def profil_complet(self):
        return bool(
            self.photo_pro.strip() and self.nom.strip() and self.prenom.strip() and self.services
        )

    @property
    def identite_figee(self):
        """Certifié, ou certification en cours d'examen : nom, prénom et
        téléphone ne bougent plus, les services ne peuvent plus être retirés."""
        if self.identite_verifiee:
            return True
        return self.verifications.filter(statut="en_attente").exists()


class Entreprise(models.Model):
    utilisateur = models.OneToOneField(
        Utilisateur, on_delete=models.CASCADE, primary_key=True, related_name="entreprise"
    )
    nom_entreprise = models.CharField(max_length=150)
    secteur_activite = models.CharField("secteur d'activité", max_length=100)
    telephone = models.CharField("téléphone", max_length=20)
    logo = models.CharField(max_length=255, blank=True)

    class Meta:
        verbose_name = "entreprise"

    def __str__(self):
        return self.nom_entreprise


class AppareilPush(models.Model):
    """Jeton Firebase d'un appareil (un utilisateur peut en avoir plusieurs)."""

    utilisateur = models.ForeignKey(
        Utilisateur, on_delete=models.CASCADE, related_name="appareils"
    )
    fcm_token = models.CharField(max_length=255, unique=True)
    plateforme = models.CharField(max_length=20, default="android")
    cree_le = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "appareil"
