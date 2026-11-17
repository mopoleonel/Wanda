from django.contrib import admin

from noyau.admin_outils import apercu

from .models import Signalement


@admin.register(Signalement)
class SignalementAdmin(admin.ModelAdmin):
    list_display = ["cree_le", "type_probleme", "statut", "entreprise", "citoyen"]
    list_filter = ["statut", "type_probleme"]
    search_fields = ["type_probleme", "citoyen__telephone", "entreprise__nom_entreprise"]
    list_select_related = ["entreprise", "citoyen"]
    readonly_fields = ["photo", "cree_le", "modifie_le"]
    raw_id_fields = ["citoyen", "entreprise"]

    @admin.display(description="photo")
    def photo(self, obj):
        return apercu(obj.image)
