"""Vérification d'identité des prestataires (CNI camerounaise + selfie).

Ce qui est gardé (minimisation) : l'identité lue sur la carte, les photos
recto / verso et le selfie (stockage privé), la preuve du consentement et un
journal horodaté de chaque étape. La comparaison selfie / carte est faite par
l'équipe WANDA dans l'administration ; le badge « Identité vérifiée » suit sa
décision.
"""
import uuid

from django.conf import settings
from django.db import models
from django.db.models import Q

from comptes.models import Prestataire


class Verification(models.Model):
    class Statut(models.TextChoices):
        EN_ATTENTE = "en_attente", "En attente"
        VALIDE = "valide", "Validée"
        REJETE = "rejete", "Rejetée"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    # PROTECT : une vérification reste disponible en cas de litige, même si
    # le compte est supprimé.
    prestataire = models.ForeignKey(
        Prestataire, on_delete=models.PROTECT, related_name="verifications"
    )
    type_document = models.CharField(max_length=20, default="CNI_CM")

    numero_document = models.CharField("numéro du document", max_length=50, blank=True)
    nom = models.CharField(max_length=100)
    prenoms = models.CharField("prénoms", max_length=150)
    date_naissance = models.DateField(null=True, blank=True)
    lieu_naissance = models.CharField(max_length=100, blank=True)
    sexe = models.CharField(max_length=1, choices=[("M", "M"), ("F", "F")], blank=True)
    date_expiration = models.DateField(null=True, blank=True)

    mrz_presente = models.BooleanField("MRZ présente", default=False)
    mrz_valide = models.BooleanField("MRZ valide", default=False)
    saisie_corrigee = models.BooleanField("nom retouché à la main", default=False)

    recto = models.CharField(max_length=255)
    verso = models.CharField(max_length=255)
    selfie = models.CharField(max_length=255)

    consentement_le = models.DateTimeField()
    consentement_version = models.CharField(max_length=20)
    consentement_texte = models.TextField()

    statut = models.CharField(max_length=20, choices=Statut.choices, default=Statut.EN_ATTENTE)
    motif_rejet = models.CharField("motif du rejet", max_length=300, blank=True)
    verifie_par = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="+", verbose_name="vérifiée par",
    )
    verifie_le = models.DateTimeField(null=True, blank=True)
    cree_le = models.DateTimeField("déposée le", auto_now_add=True)

    class Meta:
        verbose_name = "vérification d'identité"
        verbose_name_plural = "vérifications d'identité"
        ordering = ["-cree_le"]
        constraints = [
            # Une même pièce ne sert qu'à un seul compte (anti-fraude).
            models.UniqueConstraint(
                fields=["numero_document"],
                condition=~Q(numero_document="") & ~Q(statut="rejete"),
                name="document_unique",
            )
        ]

    def __str__(self):
        return "{} {} ({})".format(self.prenoms, self.nom, self.get_statut_display())


class JournalVerification(models.Model):
    """Trace de chaque étape, pour un litige. Jamais modifié."""

    verification = models.ForeignKey(
        Verification, on_delete=models.PROTECT, related_name="journal"
    )
    action = models.CharField(max_length=30)
    ancien_statut = models.CharField(max_length=20, blank=True)
    nouveau_statut = models.CharField(max_length=20, blank=True)
    acteur = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name="+"
    )
    details = models.CharField(max_length=300, blank=True)
    le = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "entrée du journal"
        verbose_name_plural = "journal des vérifications"
        ordering = ["le"]
