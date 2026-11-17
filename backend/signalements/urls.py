from django.urls import path

from . import views

urlpatterns = [
    path("signalements", views.Signalements.as_view(), name="signalements"),
    path("signalements/analyse", views.AnalyserSignalement.as_view(), name="signalements-analyse"),
    path("signalements/<uuid:pk>/statut", views.AvancerSignalement.as_view(), name="signalement-statut"),
]
