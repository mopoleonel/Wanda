from django.contrib import admin

from .models import Tarif


@admin.register(Tarif)
class TarifAdmin(admin.ModelAdmin):
    """Les prix se règlent ici : modification directe dans la liste."""

    list_display = ["service", "libelle", "valeur", "unite", "modifie_le"]
    list_display_links = ["libelle"]
    list_editable = ["valeur"]
    list_filter = ["service"]
    search_fields = ["cle", "libelle"]
    readonly_fields = ["service", "cle", "unite", "modifie_le"]

    def has_add_permission(self, request):
        # Les clés sont lues par le calcul : en ajouter une ne sert à rien.
        return False

    def has_delete_permission(self, request, obj=None):
        return False
