from django.db import models

from . import calcul


class Tarif(models.Model):
    """Paramètre de prix fixé par WANDA (modifiable dans l'administration)."""

    class Unite(models.TextChoices):
        MINUTES = "min", "minutes"
        FCFA = "fcfa", "FCFA"
        POURCENT = "pourcent", "%"
        NOMBRE = "nombre", "nombre"

    service = models.CharField(max_length=20)  # global | menage | linge | dechets | nuisibles
    cle = models.CharField("clé", max_length=50)
    valeur = models.DecimalField(max_digits=10, decimal_places=2)
    unite = models.CharField("unité", max_length=10, choices=Unite.choices)
    libelle = models.CharField("libellé", max_length=200)
    modifie_le = models.DateTimeField("modifié le", auto_now=True)

    class Meta:
        verbose_name = "tarif"
        ordering = ["service", "cle"]
        constraints = [
            models.UniqueConstraint(fields=["service", "cle"], name="tarif_unique"),
            models.CheckConstraint(check=models.Q(valeur__gte=0), name="tarif_positif"),
        ]

    def __str__(self):
        return "{} · {}".format(self.service, self.libelle)


def tarifs_actuels():
    """Tous les paramètres : {service: {cle: valeur entière}} (tarifs_json)."""
    resultat = {}
    for t in Tarif.objects.all():
        resultat.setdefault(t.service, {})[t.cle] = calcul.arrondi(t.valeur)
    return resultat


def prix_demande(service, formule, frequence, reponses, produits):
    """Prix « confirmé par le serveur » (calculer_prix_demande) : les
    produits anti-nuisibles sont toujours fournis par le prestataire."""
    return calcul.calculer_prix(
        tarifs_actuels(), service, formule, frequence, reponses,
        bool(produits) or service == "nuisibles",
    )
