from django.conf import settings
from django.db import models

from noyau.champs import ChampJSON


class Notification(models.Model):
    """Message envoyé à un utilisateur. Toujours enregistré : l'app peut
    afficher l'historique même si la notification push n'est pas arrivée."""

    destinataire = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="notifications"
    )
    titre = models.CharField(max_length=120)
    corps = models.CharField(max_length=400)
    donnees = ChampJSON(default=dict, blank=True)
    lue = models.BooleanField(default=False)
    push_envoyes = models.PositiveSmallIntegerField("envois push réussis", default=0)
    cree_le = models.DateTimeField("créée le", auto_now_add=True, db_index=True)

    class Meta:
        verbose_name = "notification"
        ordering = ["-cree_le"]

    def __str__(self):
        return self.titre
