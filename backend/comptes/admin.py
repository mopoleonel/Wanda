from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from noyau.admin_outils import apercu

from .models import AppareilPush, Citoyen, CodeConnexion, Entreprise, Prestataire, Utilisateur

admin.site.site_header = "WANDA · administration"
admin.site.site_title = "WANDA"
admin.site.index_title = "Gestion de la plateforme"


@admin.register(Utilisateur)
class UtilisateurAdmin(UserAdmin):
    ordering = ["-date_creation"]
    list_display = ["telephone", "type_compte", "is_active", "is_staff", "date_creation"]
    list_filter = ["type_compte", "is_active", "is_staff"]
    search_fields = ["telephone"]
    readonly_fields = ["date_creation", "last_login"]
    fieldsets = (
        (None, {"fields": ("telephone", "type_compte", "password")}),
        ("Accès", {"fields": ("is_active", "is_staff", "is_superuser", "groups", "user_permissions")}),
        ("Dates", {"fields": ("date_creation", "last_login")}),
    )
    add_fieldsets = (
        (None, {"classes": ("wide",), "fields": ("telephone", "password1", "password2", "is_staff")}),
    )


@admin.register(Citoyen)
class CitoyenAdmin(admin.ModelAdmin):
    list_display = ["__str__", "telephone", "email"]
    search_fields = ["nom", "prenom", "telephone", "email"]
    readonly_fields = ["utilisateur", "telephone"]


@admin.register(Prestataire)
class PrestataireAdmin(admin.ModelAdmin):
    list_display = [
        "__str__", "telephone", "liste_services", "en_ligne", "identite_verifiee",
        "abonnement_expire_le",
    ]
    list_filter = ["en_ligne", "identite_verifiee", "type_abonnement"]
    search_fields = ["nom", "prenom", "telephone"]
    # Le badge suit la décision sur une vérification d'identité.
    readonly_fields = ["utilisateur", "photo", "identite_verifiee"]
    fieldsets = (
        ("Identité", {"fields": ("utilisateur", "nom", "prenom", "telephone", "photo", "identite_verifiee")}),
        ("Activité", {"fields": ("services", "en_ligne", "latitude", "longitude")}),
        ("Abonnement", {"fields": ("type_abonnement", "abonnement_expire_le", "essai_utilise")}),
    )

    @admin.display(description="services")
    def liste_services(self, obj):
        return ", ".join(obj.services) or "—"

    @admin.display(description="photo professionnelle")
    def photo(self, obj):
        return apercu(obj.photo_pro)


@admin.register(Entreprise)
class EntrepriseAdmin(admin.ModelAdmin):
    list_display = ["nom_entreprise", "secteur_activite", "telephone"]
    list_filter = ["secteur_activite"]
    search_fields = ["nom_entreprise", "telephone"]
    readonly_fields = ["utilisateur"]


@admin.register(CodeConnexion)
class CodeConnexionAdmin(admin.ModelAdmin):
    """Lecture seule : utile pour diagnostiquer un client qui ne reçoit pas
    son code (le code lui-même n'est jamais stocké en clair)."""

    list_display = ["telephone", "cree_le", "expire_le", "essais", "utilise"]
    search_fields = ["telephone"]
    readonly_fields = ["telephone", "cree_le", "expire_le", "essais", "utilise"]
    exclude = ["empreinte"]

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False


@admin.register(AppareilPush)
class AppareilPushAdmin(admin.ModelAdmin):
    list_display = ["utilisateur", "plateforme", "cree_le"]
    search_fields = ["utilisateur__telephone"]
    readonly_fields = ["utilisateur", "fcm_token", "plateforme", "cree_le"]
