"""Envoi des notifications : enregistrement en base, puis push Firebase
(FCM v1) vers chaque appareil du destinataire si FCM_COMPTE_SERVICE est
configuré. Le push part après la validation de la transaction : une action
annulée n'envoie rien. Un échec du push ne fait jamais échouer l'action.
"""
import json
import logging
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt
from django.conf import settings
from django.db import transaction

from .models import Notification

journal = logging.getLogger("wanda.notifications")

_jeton_google = {"valeur": None, "expire": 0}
_verrou = threading.Lock()


def libelle_service(code):
    return {
        "menage": "Ménage",
        "linge": "Linge",
        "dechets": "Ramassage des poubelles",
        "nuisibles": "Lutte contre les nuisibles",
    }.get(code or "", "Service")


def montant(x):
    return "{:,}".format(x or 0).replace(",", " ") + " FCFA"


def notifier(destinataire, titre, corps, **donnees):
    donnees = {k: str(v) for k, v in donnees.items()}
    n = Notification.objects.create(
        destinataire=destinataire, titre=titre[:120], corps=corps[:400], donnees=donnees
    )
    if settings.FCM_COMPTE_SERVICE:
        transaction.on_commit(lambda: _envoyer_push(n.pk))
    return n


def _compte_service():
    with open(settings.FCM_COMPTE_SERVICE, encoding="utf8") as f:
        return json.load(f)


def _acces_google(compte):
    """Jeton OAuth2 d'accès à FCM, à partir du compte de service (mis en
    cache jusqu'à son expiration)."""
    with _verrou:
        if _jeton_google["valeur"] and _jeton_google["expire"] > time.time() + 60:
            return _jeton_google["valeur"]
        maintenant = int(time.time())
        assertion = jwt.encode(
            {
                "iss": compte["client_email"],
                "scope": "https://www.googleapis.com/auth/firebase.messaging",
                "aud": compte["token_uri"],
                "iat": maintenant,
                "exp": maintenant + 3600,
            },
            compte["private_key"],
            algorithm="RS256",
        )
        corps = urllib.parse.urlencode(
            {"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": assertion}
        ).encode()
        with urllib.request.urlopen(
            urllib.request.Request(compte["token_uri"], data=corps), timeout=10
        ) as r:
            reponse = json.loads(r.read())
        _jeton_google["valeur"] = reponse["access_token"]
        _jeton_google["expire"] = maintenant + int(reponse.get("expires_in", 3600))
        return _jeton_google["valeur"]


def _envoyer_push(notification_id):
    from comptes.models import AppareilPush

    n = Notification.objects.select_related("destinataire").get(pk=notification_id)
    jetons = list(
        AppareilPush.objects.filter(utilisateur=n.destinataire).values_list("fcm_token", flat=True)
    )
    if not jetons:
        return
    try:
        compte = _compte_service()
        acces = _acces_google(compte)
    except (OSError, KeyError, ValueError, urllib.error.URLError) as exc:
        journal.error("Push impossible (configuration Firebase) : %s", exc)
        return
    url = "https://fcm.googleapis.com/v1/projects/{}/messages:send".format(compte["project_id"])
    envoyes = 0
    for jeton in jetons:
        message = {
            "message": {
                "token": jeton,
                "notification": {"title": n.titre, "body": n.corps},
                "data": n.donnees,
            }
        }
        requete = urllib.request.Request(
            url,
            data=json.dumps(message).encode(),
            headers={"Authorization": "Bearer " + acces, "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(requete, timeout=10):
                envoyes += 1
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                # Application désinstallée : le jeton ne sert plus.
                AppareilPush.objects.filter(fcm_token=jeton).delete()
            else:
                journal.warning("Push refusé (%s) pour %s", exc.code, n.destinataire_id)
        except urllib.error.URLError as exc:
            journal.warning("Push impossible : %s", exc)
    Notification.objects.filter(pk=n.pk).update(push_envoyes=envoyes)
