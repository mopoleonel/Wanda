from django import forms
from django.contrib import admin, messages

from noyau.admin_outils import apercu

from . import services
from .models import JournalVerification, Verification


class JournalEnLigne(admin.TabularInline):
    model = JournalVerification
    extra = 0
    can_delete = False
    readonly_fields = ["le", "action", "ancien_statut", "nouveau_statut", "acteur", "details"]

    def has_add_permission(self, request, obj=None):
        return False


class DecisionForm(forms.ModelForm):
    decision = forms.ChoiceField(
        label="Décision",
        required=False,
        choices=[("", "— pas encore —"), ("valider", "Valider l'identité"), ("rejeter", "Rejeter")],
        help_text="Comparez le selfie à la photo de la carte et le nom au profil.",
    )

    class Meta:
        model = Verification
        fields = ["motif_rejet"]


@admin.register(Verification)
class VerificationAdmin(admin.ModelAdmin):
    """Examen des certifications : pièces côte à côte, puis décision. Le
    badge du prestataire et le journal sont mis à jour automatiquement."""

    form = DecisionForm
    list_display = ["cree_le", "prenoms", "nom", "numero_document", "mrz_valide", "statut"]
    list_filter = ["statut", "mrz_valide", "saisie_corrigee"]
    search_fields = ["nom", "prenoms", "numero_document", "prestataire__telephone"]
    inlines = [JournalEnLigne]
    actions = ["valider", "rejeter"]
    readonly_fields = [
        "prestataire", "statut", "piece_recto", "piece_verso", "piece_selfie",
        "nom", "prenoms", "numero_document", "date_naissance", "lieu_naissance", "sexe",
        "date_expiration", "mrz_presente", "mrz_valide", "saisie_corrigee",
        "consentement_le", "consentement_version", "consentement_texte",
        "verifie_par", "verifie_le", "cree_le",
    ]
    fieldsets = (
        ("Pièces", {"fields": ("piece_recto", "piece_verso", "piece_selfie")}),
        ("Identité lue sur la carte", {"fields": (
            "prestataire", "nom", "prenoms", "numero_document", "date_naissance",
            "lieu_naissance", "sexe", "date_expiration", "mrz_presente", "mrz_valide",
            "saisie_corrigee",
        )}),
        ("Décision", {"fields": ("statut", "decision", "motif_rejet", "verifie_par", "verifie_le")}),
        ("Consentement", {"classes": ("collapse",), "fields": (
            "consentement_le", "consentement_version", "consentement_texte",
        )}),
    )

    @admin.display(description="recto")
    def piece_recto(self, obj):
        return apercu(obj.recto, 240)

    @admin.display(description="verso")
    def piece_verso(self, obj):
        return apercu(obj.verso, 240)

    @admin.display(description="selfie")
    def piece_selfie(self, obj):
        return apercu(obj.selfie, 240)

    def save_model(self, request, obj, form, change):
        decision = form.cleaned_data.get("decision")
        if decision and obj.statut == "en_attente":
            services.decider(obj, request.user, decision == "valider",
                             form.cleaned_data.get("motif_rejet", ""))
        # Rien d'autre ne se modifie ici : une vérification est une preuve.

    @admin.action(description="Valider les vérifications choisies")
    def valider(self, request, queryset):
        n = 0
        for v in queryset.filter(statut="en_attente"):
            services.decider(v, request.user, True)
            n += 1
        self.message_user(request, "{} vérification(s) validée(s).".format(n), messages.SUCCESS)

    @admin.action(description="Rejeter (pièce non conforme)")
    def rejeter(self, request, queryset):
        n = 0
        for v in queryset.filter(statut="en_attente"):
            services.decider(v, request.user, False, "Pièce non conforme")
            n += 1
        self.message_user(request, "{} vérification(s) rejetée(s).".format(n), messages.WARNING)

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
