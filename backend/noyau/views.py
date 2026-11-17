import mimetypes

from django.http import FileResponse, Http404
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from . import stockage


@api_view(["GET"])
@permission_classes([AllowAny])
def sante(request):
    """Pour la supervision : le serveur répond."""
    return Response({"statut": "ok"})


@api_view(["GET"])
@permission_classes([AllowAny])
def fichier_signe(request, jeton):
    """Téléchargement d'une photo privée par lien signé (voir stockage)."""
    chemin = stockage.lire_jeton(jeton)
    if not stockage.existe(chemin):
        raise Http404
    type_mime = mimetypes.guess_type(chemin)[0] or "application/octet-stream"
    reponse = FileResponse(stockage.ouvrir(chemin), content_type=type_mime)
    reponse["Cache-Control"] = "private, max-age=300"
    return reponse
