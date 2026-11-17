from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from . import views

urlpatterns = [
    path("auth/code", views.EnvoyerCode.as_view(), name="auth-code"),
    path("auth/connexion", views.Connexion.as_view(), name="auth-connexion"),
    path("auth/rafraichir", TokenRefreshView.as_view(), name="auth-rafraichir"),
    path("moi", views.Moi.as_view(), name="moi"),
    path("moi/citoyen", views.MonProfilCitoyen.as_view(), name="moi-citoyen"),
    path("moi/prestataire", views.MonProfilPrestataire.as_view(), name="moi-prestataire"),
    path("moi/prestataire/en-ligne", views.EnLigne.as_view(), name="moi-en-ligne"),
    path("moi/prestataire/essai", views.EssaiGratuit.as_view(), name="moi-essai"),
    path("moi/entreprise", views.MonEntreprise.as_view(), name="moi-entreprise"),
    path("moi/photo", views.MaPhoto.as_view(), name="moi-photo"),
    path("moi/appareils", views.Appareils.as_view(), name="moi-appareils"),
    path("moi/appareils/<str:jeton>", views.Appareil.as_view(), name="moi-appareil"),
    path("prestataires", views.PrestatairesDisponibles.as_view(), name="prestataires"),
    path("prestataires/<uuid:pk>", views.PrestataireDetail.as_view(), name="prestataire"),
]
