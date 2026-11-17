from datetime import timedelta
from unittest import mock

from django.core.cache import cache
from django.test import TestCase, override_settings
from django.utils import timezone

from noyau.essais import EssaiAvecFichiers, client_de, creer_citoyen, creer_prestataire, photo
from noyau.telephone import normaliser

from .models import CodeConnexion, Prestataire, Utilisateur

TESTS = {"+237690000001": "123456", "+237690000002": "123456"}


class Telephone(TestCase):
    def test_formats_comme_dans_l_app(self):
        self.assertEqual(normaliser("690 00 00 01"), "+237690000001")
        self.assertEqual(normaliser("237690000001"), "+237690000001")
        self.assertEqual(normaliser("00237690000001"), "+237690000001")
        self.assertEqual(normaliser("+33 6 12 34 56 78"), "+33612345678")
        self.assertIsNone(normaliser("abc"))
        self.assertIsNone(normaliser(""))


@override_settings(OTP_NUMEROS_TEST=TESTS, OTP_FOURNISSEUR="console")
class ConnexionParCode(TestCase):
    def setUp(self):
        cache.clear()  # compteurs des limites d'envoi
        self.client = client_de()

    def connexion(self, telephone="690000002", code="123456", type_compte="citoyen"):
        self.client.post("/api/auth/code", {"telephone": telephone}, format="json")
        return self.client.post(
            "/api/auth/connexion",
            {"telephone": telephone, "code": code, "type_compte": type_compte},
            format="json",
        )

    def test_premier_passage_cree_le_compte_et_le_profil(self):
        r = self.connexion()
        self.assertEqual(r.status_code, 200, r.content)
        d = r.json()
        self.assertTrue(d["nouveau"])
        self.assertEqual(d["utilisateur"]["telephone"], "+237690000002")
        self.assertEqual(d["utilisateur"]["type_compte"], "citoyen")
        self.assertEqual(d["profil"]["telephone"], "+237690000002")
        self.assertEqual(d["profil"]["nom"], "")

        # Le jeton donne accès à l'API.
        moi = client_de()
        moi.credentials(HTTP_AUTHORIZATION="Bearer " + d["acces"])
        self.assertEqual(moi.get("/api/moi").json()["utilisateur"]["type_compte"], "citoyen")

        # Deuxième connexion : même compte.
        self.assertFalse(self.connexion().json()["nouveau"])
        self.assertEqual(Utilisateur.objects.count(), 1)

    def test_code_a_usage_unique(self):
        self.assertEqual(self.connexion().status_code, 200)
        r = self.client.post("/api/auth/connexion",
                             {"telephone": "690000002", "code": "123456"}, format="json")
        self.assertEqual(r.json()["code"], "CODE_INVALIDE")

    def test_mauvais_code_puis_trop_d_essais(self):
        self.client.post("/api/auth/code", {"telephone": "690000002"}, format="json")
        for _ in range(5):
            r = self.client.post("/api/auth/connexion",
                                 {"telephone": "690000002", "code": "000000"}, format="json")
            self.assertEqual(r.json()["code"], "CODE_INVALIDE")
        r = self.client.post("/api/auth/connexion",
                             {"telephone": "690000002", "code": "123456"}, format="json")
        self.assertEqual(r.json()["code"], "TROP_D_ESSAIS")

    def test_code_expire(self):
        self.client.post("/api/auth/code", {"telephone": "690000002"}, format="json")
        CodeConnexion.objects.update(expire_le=timezone.now() - timedelta(seconds=1))
        r = self.client.post("/api/auth/connexion",
                             {"telephone": "690000002", "code": "123456"}, format="json")
        self.assertEqual(r.json()["code"], "CODE_EXPIRE")

    def test_code_jamais_stocke_en_clair(self):
        self.client.post("/api/auth/code", {"telephone": "690000002"}, format="json")
        self.assertNotIn("123456", CodeConnexion.objects.get().empreinte)

    def test_un_numero_un_seul_type_de_compte(self):
        self.connexion(type_compte="citoyen")
        r = self.connexion(type_compte="particulier")
        self.assertEqual(r.status_code, 409)
        self.assertEqual(r.json()["code"], "TYPE_COMPTE_FIGE")

    def test_limite_d_envoi_par_numero(self):
        for _ in range(5):
            self.client.post("/api/auth/code", {"telephone": "690000002"}, format="json")
        r = self.client.post("/api/auth/code", {"telephone": "690000002"}, format="json")
        self.assertEqual(r.json()["code"], "TROP_DE_DEMANDES")
        # Un autre numéro, depuis la même adresse IP, passe encore.
        r = self.client.post("/api/auth/code", {"telephone": "690000001"}, format="json")
        self.assertEqual(r.status_code, 200)

    def test_numero_invalide(self):
        r = self.client.post("/api/auth/code", {"telephone": "12"}, format="json")
        self.assertEqual(r.json()["code"], "TELEPHONE_INVALIDE")

    @override_settings(OTP_NUMEROS_TEST={})
    def test_code_ecrit_dans_le_journal_en_developpement(self):
        with self.assertLogs("wanda.otp", "INFO") as journal:
            self.client.post("/api/auth/code", {"telephone": "699111222"}, format="json")
        self.assertIn("+237699111222", journal.output[0])

    @override_settings(OTP_NUMEROS_TEST={}, OTP_FOURNISSEUR="twilio", TWILIO_ACCOUNT_SID="AC1",
                       TWILIO_AUTH_TOKEN="t", TWILIO_WHATSAPP_FROM="whatsapp:+1415")
    def test_envoi_whatsapp_par_twilio(self):
        reponse = mock.MagicMock()
        reponse.__enter__.return_value.read.return_value = b'{"sid": "SM1"}'
        with mock.patch("urllib.request.urlopen", return_value=reponse) as envoi:
            r = self.client.post("/api/auth/code", {"telephone": "699111222"}, format="json")
        self.assertEqual(r.status_code, 200)
        requete = envoi.call_args[0][0]
        self.assertIn("/Accounts/AC1/Messages.json", requete.full_url)
        self.assertIn(b"whatsapp%3A%2B237699111222", requete.data)


class ProfilPrestataire(EssaiAvecFichiers):
    def setUp(self):
        self.u = creer_prestataire(services=["menage"], en_ligne=False, abonne=False)
        self.client = client_de(self.u)

    def test_services_valides_seulement(self):
        r = self.client.patch("/api/moi/prestataire", {"services": ["plombier"]}, format="json")
        self.assertEqual(r.status_code, 400)
        r = self.client.patch("/api/moi/prestataire", {"services": ["linge", "menage", "linge"]},
                              format="json")
        self.assertEqual(r.json()["services"], ["menage", "linge"])

    def test_identite_figee_apres_certification(self):
        Prestataire.objects.filter(pk=self.u.pk).update(identite_verifiee=True)
        r = self.client.patch("/api/moi/prestataire", {"nom": "Autre"}, format="json")
        self.assertEqual(r.json()["code"], "IDENTITE_FIGEE")
        # Retirer un service : refusé ; en ajouter un : permis.
        r = self.client.patch("/api/moi/prestataire", {"services": ["linge"]}, format="json")
        self.assertEqual(r.json()["code"], "IDENTITE_FIGEE")
        r = self.client.patch("/api/moi/prestataire", {"services": ["menage", "linge"]},
                              format="json")
        self.assertEqual(r.status_code, 200)
        # Le badge ne s'attribue pas soi-même.
        self.client.patch("/api/moi/prestataire", {"identite_verifiee": False}, format="json")
        self.assertTrue(Prestataire.objects.get(pk=self.u.pk).identite_verifiee)

    def test_en_ligne_seulement_avec_un_abonnement(self):
        r = self.client.post("/api/moi/prestataire/en-ligne", {"en_ligne": True}, format="json")
        self.assertEqual(r.json()["code"], "ABONNEMENT_REQUIS")
        r = self.client.post("/api/moi/prestataire/essai")
        self.assertEqual(r.json()["type_abonnement"], "ESSAI")
        self.assertEqual(self.client.post("/api/moi/prestataire/essai").json()["code"],
                         "ESSAI_DEJA_UTILISE")
        r = self.client.post("/api/moi/prestataire/en-ligne",
                             {"en_ligne": True, "latitude": 4.05, "longitude": 9.77}, format="json")
        self.assertTrue(r.json()["en_ligne"])
        self.assertEqual(r.json()["latitude"], 4.05)

    def test_photo_professionnelle(self):
        r = self.client.post("/api/moi/photo", {"fichier": photo()}, format="multipart")
        self.assertEqual(r.status_code, 200, r.content)
        self.assertIn("/api/fichiers/", r.json()["photo_url"])
        # Le contenu compte, pas l'extension.
        r = self.client.post("/api/moi/photo", {"fichier": photo("x.jpg", b"pas une image")},
                             format="multipart")
        self.assertEqual(r.json()["code"], "FICHIER_INVALIDE")
        # Le lien signé donne le fichier, sans être connecté.
        lien = self.client.get("/api/moi").json()["profil"]["photo_url"]
        # Photo de profil : même adresse à chaque appel (mise en cache).
        self.assertEqual(self.client.get("/api/moi").json()["profil"]["photo_url"], lien)
        self.assertEqual(client_de().get(lien).status_code, 200)
        self.assertEqual(client_de().get(lien + "x").status_code, 403)


class ListeDesPrestataires(TestCase):
    def test_seulement_les_prestataires_reservables(self):
        creer_prestataire("+237690000011", services=["menage"])
        creer_prestataire("+237690000012", services=["linge"])
        creer_prestataire("+237690000013", services=["menage"], en_ligne=False)
        creer_prestataire("+237690000014", services=["menage"], abonne=False)
        creer_prestataire("+237690000015", services=[])
        client = client_de(creer_citoyen())
        tous = client.get("/api/prestataires").json()
        self.assertEqual(sorted(p["telephone"] for p in tous),
                         ["+237690000011", "+237690000012"])
        menage = client.get("/api/prestataires?service=menage").json()
        self.assertEqual([p["telephone"] for p in menage], ["+237690000011"])
        self.assertIsNone(menage[0]["note_moyenne"])


class Appareils(TestCase):
    def test_jeton_rattache_au_dernier_compte(self):
        a, b = creer_citoyen(), creer_prestataire()
        client_de(a).post("/api/moi/appareils", {"fcm_token": "tok"}, format="json")
        client_de(b).post("/api/moi/appareils", {"fcm_token": "tok"}, format="json")
        self.assertEqual(list(b.appareils.values_list("fcm_token", flat=True)), ["tok"])
        self.assertFalse(a.appareils.exists())
        client_de(b).delete("/api/moi/appareils/tok")
        self.assertFalse(b.appareils.exists())


class TypeDeCompteApresConnexion(TestCase):
    def test_choisir_prestataire_puis_type_fige(self):
        u = Utilisateur.objects.create_user("+237690000055")
        c = client_de(u)
        r = c.post("/api/moi/type", {"type_compte": "particulier"}, format="json")
        self.assertEqual(r.status_code, 200, r.content)
        self.assertEqual(r.json()["profil"]["telephone"], "+237690000055")
        r = c.post("/api/moi/type", {"type_compte": "citoyen"}, format="json")
        self.assertEqual(r.json()["code"], "TYPE_COMPTE_FIGE")

    def test_entreprise_creee_puis_retiree(self):
        u = Utilisateur.objects.create_user("+237690000056")
        c = client_de(u)
        r = c.put("/api/moi/entreprise", {"nom_entreprise": "Eau Pro",
                                          "secteur_activite": "Sécurité Publique"}, format="json")
        self.assertEqual(r.status_code, 201, r.content)
        self.assertEqual(c.delete("/api/moi/entreprise").status_code, 204)
        u.refresh_from_db()
        self.assertEqual(u.type_compte, "")
        self.assertFalse(hasattr(Utilisateur.objects.get(pk=u.pk), "entreprise"))
