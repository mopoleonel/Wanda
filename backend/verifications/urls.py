from django.urls import path

from . import views

urlpatterns = [
    path("moi/certification", views.Certification.as_view(), name="certification"),
]
