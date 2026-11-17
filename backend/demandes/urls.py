from django.urls import path

from . import views

urlpatterns = [
    path("demandes", views.MesDemandes.as_view(), name="demandes"),
    path("demandes/analyse", views.Analyser.as_view(), name="demandes-analyse"),
    path("demandes/<uuid:pk>", views.DemandeDetail.as_view(), name="demande"),
    path("demandes/<uuid:pk>/ajustements", views.Ajustements.as_view(), name="demande-ajustements"),
    path("demandes/<uuid:pk>/passages", views.Passages.as_view(), name="demande-passages"),
    path("demandes/<uuid:pk>/avis", views.Noter.as_view(), name="demande-avis"),
    path(
        "demandes/<uuid:pk>/<str:action>",
        views.ChangerStatut.as_view(),
        name="demande-action",
    ),
    path(
        "ajustements/<uuid:pk>/repondre",
        views.RepondreAjustement.as_view(),
        name="ajustement-repondre",
    ),
    path("prestataires/<uuid:pk>/avis", views.AvisPrestataire.as_view(), name="prestataire-avis"),
    path("notes", views.Notes.as_view(), name="notes"),
    path("photos", views.EnvoyerPhoto.as_view(), name="photos"),
    path("photos/lien", views.LienPhoto.as_view(), name="photo-lien"),
]
