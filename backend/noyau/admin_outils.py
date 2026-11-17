"""Aperçu des photos privées dans l'administration (équipe WANDA seulement)."""
from urllib.parse import urlencode

from django.contrib.admin.views.decorators import staff_member_required
from django.http import FileResponse, Http404
from django.urls import reverse
from django.utils.html import format_html, format_html_join

from . import stockage


def _url(chemin):
    return reverse("admin-fichier") + "?" + urlencode({"chemin": chemin})


def apercu(chemin, hauteur=160):
    if not chemin:
        return "—"
    return format_html(
        '<a href="{0}" target="_blank" rel="noopener">'
        '<img src="{0}" style="max-height:{1}px;border-radius:6px" alt=""></a>',
        _url(chemin),
        hauteur,
    )


def apercus(chemins, hauteur=120):
    if not chemins:
        return "—"
    return format_html_join(" ", "{}", ((apercu(c, hauteur),) for c in chemins))


@staff_member_required
def fichier_admin(request):
    chemin = request.GET.get("chemin", "")
    if ".." in chemin.split("/") or not stockage.existe(chemin):
        raise Http404
    return FileResponse(stockage.ouvrir(chemin))
