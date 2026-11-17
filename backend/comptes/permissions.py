from rest_framework.permissions import BasePermission


class EstCitoyen(BasePermission):
    def has_permission(self, request, view):
        return hasattr(request.user, "citoyen")


class EstPrestataire(BasePermission):
    def has_permission(self, request, view):
        return hasattr(request.user, "prestataire")


class EstEntreprise(BasePermission):
    def has_permission(self, request, view):
        return hasattr(request.user, "entreprise")
