"""Codes de connexion à 6 chiffres.

Fournisseurs (réglage OTP_FOURNISSEUR) :
  console : le code est écrit dans le journal (développement) ;
  twilio  : envoi par WhatsApp via l'API Twilio.
Les numéros de OTP_NUMEROS_TEST ont un code fixe et ne reçoivent rien (même
principe que les « numéros de test » de Supabase).
"""
import base64
import json
import logging
import secrets
import urllib.error
import urllib.parse
import urllib.request
from datetime import timedelta

from django.conf import settings
from django.contrib.auth.hashers import check_password, make_password
from django.db import transaction
from django.utils import timezone

from noyau.erreurs import ErreurMetier

from .models import CodeConnexion

journal = logging.getLogger("wanda.otp")


def _code_pour(telephone):
    return settings.OTP_NUMEROS_TEST.get(telephone) or "{:06d}".format(
        secrets.randbelow(1000000)
    )


def envoyer_code(telephone):
    code = _code_pour(telephone)
    with transaction.atomic():
        # Un nouveau code invalide les précédents.
        CodeConnexion.objects.filter(telephone=telephone, utilise=False).update(utilise=True)
        CodeConnexion.objects.create(
            telephone=telephone,
            empreinte=make_password(code),
            expire_le=timezone.now() + timedelta(seconds=settings.OTP_DUREE),
        )
    if telephone in settings.OTP_NUMEROS_TEST:
        return
    if settings.OTP_FOURNISSEUR == "twilio":
        _envoyer_twilio(telephone, code)
    else:
        journal.info("Code de connexion pour %s : %s", telephone, code)


def verifier_code(telephone, code):
    """Valide le code (usage unique). Lève une ErreurMetier sinon.

    L'erreur est levée APRÈS la transaction : un essai raté doit rester
    compté (une exception à l'intérieur annulerait l'incrément)."""
    erreur = None
    with transaction.atomic():
        dernier = (
            CodeConnexion.objects.select_for_update()
            .filter(telephone=telephone, utilise=False)
            .order_by("-cree_le")
            .first()
        )
        if dernier is None:
            erreur = "CODE_INVALIDE"
        elif dernier.expire_le < timezone.now():
            erreur = "CODE_EXPIRE"
        elif dernier.essais >= settings.OTP_ESSAIS_MAX:
            erreur = "TROP_D_ESSAIS"
        elif not check_password(code or "", dernier.empreinte):
            dernier.essais += 1
            dernier.save(update_fields=["essais"])
            erreur = "CODE_INVALIDE"
        else:
            dernier.utilise = True
            dernier.save(update_fields=["utilise"])
    if erreur:
        raise ErreurMetier(erreur)


def _envoyer_twilio(telephone, code):
    sid, jeton = settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN
    if not (sid and jeton and settings.TWILIO_WHATSAPP_FROM):
        journal.error("Twilio n'est pas configuré : code non envoyé à %s", telephone)
        raise ErreurMetier("ENVOI_CODE_IMPOSSIBLE", status_code=503)
    corps = urllib.parse.urlencode(
        {
            "From": settings.TWILIO_WHATSAPP_FROM,
            "To": "whatsapp:" + telephone,
            "Body": "Votre code WANDA : {}. Il expire dans 5 minutes. "
            "Ne le communiquez à personne.".format(code),
        }
    ).encode()
    requete = urllib.request.Request(
        "https://api.twilio.com/2010-04-01/Accounts/{}/Messages.json".format(sid),
        data=corps,
        headers={
            "Authorization": "Basic "
            + base64.b64encode("{}:{}".format(sid, jeton).encode()).decode(),
            "Content-Type": "application/x-www-form-urlencoded",
        },
    )
    try:
        with urllib.request.urlopen(requete, timeout=15) as reponse:
            json.loads(reponse.read() or b"{}")
    except (urllib.error.URLError, ValueError) as exc:
        journal.error("Échec de l'envoi Twilio à %s : %s", telephone, exc)
        raise ErreurMetier("ENVOI_CODE_IMPOSSIBLE", status_code=503)
