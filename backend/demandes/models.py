"""Demandes de service (table « sollicitations » de Supabase), ajustements,
passages d'abonnement, analyses IA et avis.

Les colonnes de prix ne sont écrites que par services.py : l'API n'expose
aucune modification directe d'une demande.
"""
import uuid

from django.db import models
from django.db.models import Q

from noyau.champs import ChampJSON

from comptes.models import SERVICES, Citoyen, Prestataire


class Demande(models.Model):
    class Statut(models.TextChoices):
        EN_ATTENTE = "en_attente", "Reçue"
        ACCEPTE = "accepte", "Confirmée"
        REFUSE = "refuse", "Refusée"
        TERMINE = "termine", "Terminée"
        ANNULE = "annule", "Annulée"
        ARCHIVE = "archive", "Classée"

    class Formule(models.TextChoices):
        PONCTUELLE = "ponctuelle", "Une fois"
        ABONNEMENT = "abonnement", "Abonnement"

    class Frequence(models.TextChoices):
        HEBDOMADAIRE = "hebdomadaire", "Chaque semaine"
        MENSUEL = "mensuel", "Chaque mois"

    class Creneau(models.TextChoices):
        MATIN = "matin", "Matin"
        APRES_MIDI = "apres_midi", "Après-midi"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    prestataire = models.ForeignKey(Prestataire, on_delete=models.PROTECT, related_name="demandes")
    citoyen = models.ForeignKey(Citoyen, on_delete=models.PROTECT, related_name="demandes")
    # Coordonnées du client au moment de la demande (le prestataire l'appelle).
    nom_citoyen = models.CharField(max_length=100)
    prenom_citoyen = models.CharField(max_length=100, blank=True)
    numero_citoyen = models.CharField(max_length=20)

    statut = models.CharField(max_length=20, choices=Statut.choices, default=Statut.EN_ATTENTE)
    date_sollicitation = models.DateTimeField("envoyée le", auto_now_add=True, db_index=True)
    date_fin = models.DateTimeField("terminée le", null=True, blank=True)
    modifie_le = models.DateTimeField("modifiée le", auto_now=True, db_index=True)

    service = models.CharField(max_length=20, choices=SERVICES)
    formule = models.CharField(max_length=20, choices=Formule.choices)
    frequence = models.CharField(max_length=20, choices=Frequence.choices, blank=True)
    reponses = ChampJSON("réponses", default=dict)
    produits_fournis = models.BooleanField(default=False)
    minutes_estimees = models.PositiveIntegerField()
    prix_passage = models.PositiveIntegerField()
    prix_total = models.PositiveIntegerField()
    prix_detail = ChampJSON(default=dict)
    photos = ChampJSON(default=list)
    ia_analyse = ChampJSON(null=True, blank=True)
    date_souhaitee = models.DateField("date souhaitée")
    creneau = models.CharField("créneau", max_length=20, choices=Creneau.choices)
    motif_refus = models.CharField(max_length=200, blank=True)

    class Meta:
        verbose_name = "demande"
        ordering = ["-date_sollicitation"]
        constraints = [
            models.CheckConstraint(
                check=~Q(formule="abonnement") | ~Q(frequence=""),
                name="abonnement_avec_frequence",
            )
        ]

    def __str__(self):
        return "N° {} · {}".format(numero_fiche(self.pk), self.get_service_display())


def numero_fiche(identifiant):
    """« E0FF8A » : les 6 premiers caractères, comme dans l'app."""
    return str(identifiant).replace("-", "")[:6].upper()


class AnalyseIA(models.Model):
    """Résultat de l'analyse des photos par l'IA, enregistré par le serveur
    (le client ne peut pas le falsifier)."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    citoyen = models.ForeignKey(Citoyen, on_delete=models.CASCADE, related_name="analyses")
    service = models.CharField(max_length=20, choices=SERVICES)
    reponses = ChampJSON(default=dict)
    photos = ChampJSON(default=list)
    resultat = ChampJSON(null=True, blank=True)
    erreur = models.CharField(max_length=100, blank=True)
    modele = models.CharField(max_length=100, blank=True)
    cree_le = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "analyse IA"
        verbose_name_plural = "analyses IA"
        ordering = ["-cree_le"]


class Ajustement(models.Model):
    """Supplément demandé par le prestataire (aucun paiement en plus sur
    place) : le client l'accepte ou le refuse dans l'app."""

    class Statut(models.TextChoices):
        EN_ATTENTE = "en_attente", "En attente"
        ACCEPTE = "accepte", "Accepté"
        REFUSE = "refuse", "Refusé"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    demande = models.ForeignKey(Demande, on_delete=models.PROTECT, related_name="ajustements")
    minutes_supp = models.PositiveIntegerField(default=0)
    produits_supp = models.PositiveIntegerField(default=0)
    motif = models.CharField(max_length=500)
    photos = ChampJSON(default=list, blank=True)
    prix_supp = models.PositiveIntegerField()
    statut = models.CharField(max_length=20, choices=Statut.choices, default=Statut.EN_ATTENTE)
    cree_le = models.DateTimeField(auto_now_add=True)
    repondu_le = models.DateTimeField(null=True, blank=True)

    class Meta:
        verbose_name = "ajustement"
        ordering = ["-cree_le"]
        constraints = [
            # Un seul ajustement en attente à la fois par demande.
            models.UniqueConstraint(
                fields=["demande"],
                condition=Q(statut="en_attente"),
                name="un_ajustement_en_attente",
            )
        ]


class Passage(models.Model):
    """Passage effectué d'un abonnement, pointé par le prestataire."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    demande = models.ForeignKey(Demande, on_delete=models.PROTECT, related_name="passages")
    effectue_le = models.DateTimeField(auto_now_add=True)
    jour = models.DateField()

    class Meta:
        verbose_name = "passage"
        ordering = ["-effectue_le"]
        constraints = [
            # Un passage au plus par jour (évite les doubles appuis).
            models.UniqueConstraint(fields=["demande", "jour"], name="un_passage_par_jour")
        ]


class Avis(models.Model):
    demande = models.OneToOneField(Demande, on_delete=models.CASCADE, related_name="avis")
    prestataire = models.ForeignKey(Prestataire, on_delete=models.CASCADE, related_name="avis_recus")
    citoyen = models.ForeignKey(Citoyen, on_delete=models.CASCADE, related_name="avis_donnes")
    note = models.PositiveSmallIntegerField()
    commentaire = models.CharField(max_length=500, blank=True)
    cree_le = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "avis"
        verbose_name_plural = "avis"
        ordering = ["-cree_le"]
        constraints = [
            models.CheckConstraint(check=Q(note__gte=1, note__lte=5), name="note_1_a_5")
        ]
