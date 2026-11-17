from django.urls import path

from . import views

urlpatterns = [
    path("tarifs", views.Tarifs.as_view(), name="tarifs"),
    path("prix", views.Prix.as_view(), name="prix"),
]
