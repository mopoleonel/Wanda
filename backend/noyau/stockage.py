"""Fichiers privés : photos des demandes et pièces d'identité.

Rangement : <espace>/<id auteur>/<dossier>/<nom aléatoire>.jpg, sous
MEDIA_ROOT. Rien n'est servi directement : l'API donne un lien signé valable
quelques minutes (equivalent des « URL signées » de Supabase Storage), et
seules les personnes autorisées obtiennent ce lien.

Pas de suppression ni de remplacement : ce sont des preuves en cas de litige.
"""
import uuid

from django.conf import settings
from django.core import signing
from django.core.files.storage import FileSystemStorage
from django.urls import reverse

from .erreurs import ErreurMetier

ESPACES = ("demandes", "identites", "profils", "signalements")
_TYPES = {b"\xff\xd8\xff": ".jpg", b"\x89PNG": ".png"}
_SEL = "wanda.fichier"


def _stockage():
    return FileSystemStorage(location=settings.MEDIA_ROOT)


def _extension(debut):
    for signature, ext in _TYPES.items():
        if debut.startswith(signature):
            return ext
    return None


def enregistrer(fichier, espace, auteur_id, dossier="divers"):
    """Enregistre une photo envoyée et renvoie son chemin.

    Le contenu est contrôlé (JPEG ou PNG réel, taille maximale) : le nom et
    le type annoncés par le client ne comptent pas.
    """
    if espace not in ESPACES:
        raise ValueError(espace)
    if fichier is None or fichier.size > settings.PHOTO_TAILLE_MAX:
        raise ErreurMetier("FICHIER_INVALIDE")
    debut = fichier.read(8)
    fichier.seek(0)
    ext = _extension(debut)
    if ext is None:
        raise ErreurMetier("FICHIER_INVALIDE")
    dossier = "".join(c for c in dossier if c.isalnum() or c in "-_")[:40] or "divers"
    chemin = "{}/{}/{}/{}{}".format(espace, auteur_id, dossier, uuid.uuid4().hex, ext)
    return _stockage().save(chemin, fichier)


def appartient_a(chemin, auteur_id):
    """Vrai si le chemin est dans le dossier de cet auteur (comme la règle
    « <uid>/... » des politiques Supabase)."""
    morceaux = (chemin or "").split("/")
    return len(morceaux) >= 3 and morceaux[1] == str(auteur_id) and ".." not in morceaux


def lien_signe(request, chemin):
    """Lien de téléchargement valable LIEN_PHOTO_DUREE secondes."""
    jeton = signing.dumps(chemin, salt=_SEL)
    url = reverse("fichier-signe", args=[jeton])
    return request.build_absolute_uri(url) if request is not None else url


def lire_jeton(jeton):
    try:
        return signing.loads(jeton, salt=_SEL, max_age=settings.LIEN_PHOTO_DUREE)
    except signing.SignatureExpired:
        raise ErreurMetier("LIEN_EXPIRE", status_code=403)
    except signing.BadSignature:
        raise ErreurMetier("NON_AUTORISE", status_code=403)


def ouvrir(chemin):
    return _stockage().open(chemin, "rb")


def existe(chemin):
    return _stockage().exists(chemin)
