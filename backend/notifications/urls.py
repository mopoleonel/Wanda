from django.urls import path

from . import views

urlpatterns = [
    path("notifications", views.MesNotifications.as_view(), name="notifications"),
    path("notifications/lues", views.MarquerLues.as_view(), name="notifications-lues"),
]
