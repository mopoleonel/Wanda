"""Adresses du back-end WANDA.

  /admin/                interface d'administration (équipe WANDA)
  /api/...               API de l'application mobile (voir README)
"""
from django.contrib import admin
from django.urls import include, path

from noyau import admin_outils
from noyau import views as noyau

api = [
    path("sante", noyau.sante, name="sante"),
    path("fichiers/<str:jeton>", noyau.fichier_signe, name="fichier-signe"),
    path("", include("comptes.urls")),
    path("", include("tarification.urls")),
    path("", include("demandes.urls")),
    path("", include("verifications.urls")),
    path("", include("signalements.urls")),
    path("", include("notifications.urls")),
]

urlpatterns = [
    path("admin/fichier", admin_outils.fichier_admin, name="admin-fichier"),
    path("admin/", admin.site.urls),
    path("api/", include(api)),
]
