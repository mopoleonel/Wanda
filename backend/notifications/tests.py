import json
import os
import tempfile
import urllib.error
from unittest import mock

from django.test import TestCase, override_settings

from comptes.models import AppareilPush
from noyau.essais import client_de, creer_citoyen

from . import services
from .models import Notification


class Notifications(TestCase):
    def test_enregistree_sans_firebase(self):
        u = creer_citoyen()
        services.notifier(u, "Titre", "Corps", demande="abc")
        c = client_de(u)
        liste = c.get("/api/notifications").json()["results"]
        self.assertEqual((liste[0]["titre"], liste[0]["donnees"]), ("Titre", {"demande": "abc"}))
        self.assertEqual(c.post("/api/notifications/lues").json()["lues"], 1)
        self.assertTrue(Notification.objects.get().lue)

    def test_montant_lisible(self):
        self.assertEqual(services.montant(21600), "21 600 FCFA")

    def test_push_firebase_et_jeton_perime_supprime(self):
        u = creer_citoyen()
        AppareilPush.objects.create(utilisateur=u, fcm_token="bon")
        AppareilPush.objects.create(utilisateur=u, fcm_token="perime")
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump({"project_id": "wanda-test", "client_email": "x@y",
                       "token_uri": "https://oauth2.example/token", "private_key": "k"}, f)
        self.addCleanup(os.remove, f.name)

        envoyes = []

        def urlopen(requete, timeout=None):
            envoyes.append(json.loads(requete.data))
            if envoyes[-1]["message"]["token"] == "perime":
                raise urllib.error.HTTPError(requete.full_url, 404, "absent", {}, None)
            return mock.MagicMock()

        with override_settings(FCM_COMPTE_SERVICE=f.name), \
                mock.patch.object(services, "_acces_google", return_value="jeton"), \
                mock.patch("urllib.request.urlopen", side_effect=urlopen), \
                self.captureOnCommitCallbacks(execute=True):
            services.notifier(u, "Demande confirmée", "Votre prestataire a accepté.")

        self.assertEqual(sorted(m["message"]["token"] for m in envoyes), ["bon", "perime"])
        self.assertEqual(envoyes[0]["message"]["notification"]["title"], "Demande confirmée")
        self.assertEqual(Notification.objects.get().push_envoyes, 1)
        self.assertEqual(list(AppareilPush.objects.values_list("fcm_token", flat=True)), ["bon"])
