from django.contrib import admin

from noyau.admin_outils import apercus

from .models import AnalyseIA, Ajustement, Avis, Demande, Passage, numero_fiche


class AjustementEnLigne(admin.TabularInline):
    model = Ajustement
    extra = 0
    can_delete = False
    fields = ["cree_le", "minutes_supp", "produits_supp", "prix_supp", "motif", "statut"]
    readonly_fields = fields

    def has_add_permission(self, request, obj=None):
        return False


class PassageEnLigne(admin.TabularInline):
    model = Passage
    extra = 0
    can_delete = False
    readonly_fields = ["effectue_le", "jour"]

    def has_add_permission(self, request, obj=None):
        return False


@admin.register(Demande)
class DemandeAdmin(admin.ModelAdmin):
    """Consultation et suivi. Les prix et le contenu de la demande ne se
    modifient pas : ce sont ceux calculés et acceptés dans l'app."""

    list_display = [
        "numero", "date_sollicitation", "service", "formule", "statut",
        "prix_total", "citoyen", "prestataire",
    ]
    list_filter = ["statut", "service", "formule", "date_souhaitee"]
    search_fields = ["id", "numero_citoyen", "nom_citoyen", "prestataire__nom", "prestataire__telephone"]
    list_select_related = ["citoyen", "prestataire"]
    date_hierarchy = "date_sollicitation"
    inlines = [AjustementEnLigne, PassageEnLigne]
    readonly_fields = [
        "numero", "citoyen", "prestataire", "nom_citoyen", "prenom_citoyen", "numero_citoyen",
        "date_sollicitation", "date_fin", "modifie_le", "service", "formule", "frequence",
        "reponses", "produits_fournis", "minutes_estimees", "prix_passage", "prix_total",
        "prix_detail", "apercu_photos", "ia_analyse", "date_souhaitee", "creneau",
    ]
    # Seuls le statut et le motif de refus restent corrigeables par l'équipe.
    fields = [
        "numero", "statut", "motif_refus", "citoyen", "nom_citoyen", "prenom_citoyen",
        "numero_citoyen", "prestataire", "date_sollicitation", "date_fin", "modifie_le",
        "service", "formule", "frequence", "reponses", "produits_fournis",
        "minutes_estimees", "prix_passage", "prix_total", "prix_detail",
        "apercu_photos", "ia_analyse", "date_souhaitee", "creneau",
    ]

    @admin.display(description="N°")
    def numero(self, obj):
        return numero_fiche(obj.pk)

    @admin.display(description="photos")
    def apercu_photos(self, obj):
        return apercus(obj.photos)

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(Ajustement)
class AjustementAdmin(admin.ModelAdmin):
    list_display = ["cree_le", "demande", "prix_supp", "statut"]
    list_filter = ["statut"]
    readonly_fields = [f.name for f in Ajustement._meta.fields] + ["apercu_photos"]
    exclude = ["photos"]

    @admin.display(description="photos")
    def apercu_photos(self, obj):
        return apercus(obj.photos)

    def has_add_permission(self, request):
        return False


@admin.register(Avis)
class AvisAdmin(admin.ModelAdmin):
    list_display = ["cree_le", "prestataire", "note", "commentaire"]
    list_filter = ["note"]
    search_fields = ["prestataire__nom", "commentaire"]
    readonly_fields = ["demande", "prestataire", "citoyen", "note", "cree_le"]


@admin.register(AnalyseIA)
class AnalyseIAAdmin(admin.ModelAdmin):
    list_display = ["cree_le", "service", "erreur", "modele"]
    list_filter = ["service", "erreur"]
    readonly_fields = [f.name for f in AnalyseIA._meta.fields]

    def has_add_permission(self, request):
        return False
