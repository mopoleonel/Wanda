import uuid

from django.db import models

from comptes.models import Citoyen, Entreprise


class Signalement(models.Model):
    """Incident signalé gratuitement par un citoyen (fuite, panne, dépôt
    sauvage…) et transmis à l'entreprise du secteur."""

    class Statut(models.TextChoices):
        EN_ATTENTE = "en_attente", "En attente"
        EN_COURS = "en_cours", "Pris en charge"
        RESOLU = "resolu", "Résolu"
        REJETE = "rejete", "Rejeté"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    type_probleme = models.CharField("type de problème", max_length=100)
    image = models.CharField(max_length=255)
    latitude = models.FloatField()
    longitude = models.FloatField()
    entreprise = models.ForeignKey(
        Entreprise, on_delete=models.SET_NULL, null=True, blank=True, related_name="signalements"
    )
    citoyen = models.ForeignKey(
        Citoyen, on_delete=models.SET_NULL, null=True, blank=True, related_name="signalements"
    )
    statut = models.CharField(max_length=20, choices=Statut.choices, default=Statut.EN_ATTENTE)
    ia_validation_details = models.CharField("avis de l'IA", max_length=500, blank=True)
    cree_le = models.DateTimeField("signalé le", auto_now_add=True, db_index=True)
    modifie_le = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "signalement"
        ordering = ["-cree_le"]

    def __str__(self):
        return self.type_probleme
