"""Tests exhaustifs de sécurité et d'isolation des données :
  - Côté Client : permissions, interdictions, intégrité du prix, avis
  - Côté Prestataire : permissions, transitions, ajustements, passages, identité
  - Isolation croisée : un tiers (client ou prestataire) ne peut ni voir ni manipuler les données d'autrui
"""
from datetime import timedelta
from unittest import mock

from django.contrib.auth import get_user_model
from django.utils import timezone

from comptes.models import Citoyen, Prestataire
from noyau.essais import EssaiAvecFichiers, client_de, creer_citoyen, creer_prestataire, photo
from notifications.models import Notification
from verifications import services as verif_services
from verifications.models import Verification

from .models import Ajustement, Avis, Demande, Passage

MENAGE = {"chambres": 2, "salons": 1, "cuisines": 1, "douche_wc": 1, "etat": "normal"}


class SecuriteEtIsolation(EssaiAvecFichiers):
    def setUp(self):
        self.presta = creer_prestataire("+237690000001", photo_pro="profils/p1/p.jpg")
        self.client_u = creer_citoyen("+237690000002", nom="Mbarga", prenom="Lucie")
        self.tiers_citoyen = creer_citoyen("+237690000003", nom="Intrus", prenom="Paul")
        self.tiers_presta = creer_prestataire("+237690000004", photo_pro="profils/p2/p.jpg")

        self.c = client_de(self.client_u)
        self.p = client_de(self.presta)
        self.c_tiers = client_de(self.tiers_citoyen)
        self.p_tiers = client_de(self.tiers_presta)
        self.anonyme = client_de()

    def reserver(self, client=None, presta=None, **champs):
        client = client or self.c
        presta = presta or self.presta
        donnees = {
            "prestataire": str(presta.pk),
            "service": "menage",
            "formule": "ponctuelle",
            "reponses": MENAGE,
            "produits": False,
            "photos": [self.envoyer_photo(client)],
            "date_souhaitee": str(timezone.localdate() + timedelta(days=1)),
            "creneau": "matin",
        }
        donnees.update(champs)
        return client.post("/api/demandes", donnees, format="json")

    # =========================================================================
    # 1. Sécurité Côté Client
    # =========================================================================

    def test_client_ne_peut_pas_accepter_ou_terminer_sa_propre_demande(self):
        demande = self.reserver().json()["id"]
        url = f"/api/demandes/{demande}"

        # Le client tente d'accepter
        r_acc = self.c.post(f"{url}/accepter")
        self.assertEqual(r_acc.json()["code"], "TRANSITION_INTERDITE")

        # Le client tente de refuser
        r_ref = self.c.post(f"{url}/refuser", {"motif": "x"}, format="json")
        self.assertEqual(r_ref.json()["code"], "TRANSITION_INTERDITE")

        # Le client tente de terminer
        r_term = self.c.post(f"{url}/terminer")
        self.assertEqual(r_term.json()["code"], "TRANSITION_INTERDITE")

    def test_client_ne_peut_pas_demander_d_ajustement(self):
        demande = self.reserver().json()["id"]
        url = f"/api/demandes/{demande}"
        self.p.post(f"{url}/accepter")

        r = self.c.post(f"{url}/ajustements", {"minutes": 30, "motif": "Triche"}, format="json")
        self.assertEqual(r.status_code, 403)

    def test_client_ne_peut_pas_pointer_de_passage(self):
        abo = self.reserver(formule="abonnement", frequence="hebdomadaire").json()["id"]
        url = f"/api/demandes/{abo}"
        self.p.post(f"{url}/accepter")

        r = self.c.post(f"{url}/passages")
        self.assertIn(r.json()["code"], ("NON_AUTORISE", "PASSAGE_IMPOSSIBLE"))

    def test_client_ne_peut_pas_noter_avant_fin_de_mission(self):
        demande = self.reserver().json()["id"]
        url = f"/api/demandes/{demande}"

        # En attente : refus
        r = self.c.post(f"{url}/avis", {"note": 5}, format="json")
        self.assertEqual(r.json()["code"], "AVIS_IMPOSSIBLE")

        # Acceptée mais pas terminée : refus
        self.p.post(f"{url}/accepter")
        r = self.c.post(f"{url}/avis", {"note": 5}, format="json")
        self.assertEqual(r.json()["code"], "AVIS_IMPOSSIBLE")

    def test_note_hors_bornes_refusee(self):
        demande = self.reserver().json()["id"]
        url = f"/api/demandes/{demande}"
        self.p.post(f"{url}/accepter")
        self.p.post(f"{url}/terminer")

        r_zero = self.c.post(f"{url}/avis", {"note": 0}, format="json")
        self.assertEqual(r_zero.status_code, 400)
        r_six = self.c.post(f"{url}/avis", {"note": 6}, format="json")
        self.assertEqual(r_six.status_code, 400)

    def test_double_avis_interdit(self):
        demande = self.reserver().json()["id"]
        url = f"/api/demandes/{demande}"
        self.p.post(f"{url}/accepter")
        self.p.post(f"{url}/terminer")

        r1 = self.c.post(f"{url}/avis", {"note": 5, "commentaire": "Top"}, format="json")
        self.assertEqual(r1.status_code, 201)
        r2 = self.c.post(f"{url}/avis", {"note": 4}, format="json")
        self.assertEqual(r2.json()["code"], "AVIS_DEJA_DONNE")

    # =========================================================================
    # 2. Sécurité Côté Prestataire
    # =========================================================================

    def test_prestataire_ne_peut_pas_annuler_ou_classer(self):
        demande = self.reserver().json()["id"]
        url = f"/api/demandes/{demande}"

        r_ann = self.p.post(f"{url}/annuler")
        self.assertEqual(r_ann.json()["code"], "TRANSITION_INTERDITE")

        self.p.post(f"{url}/accepter")
        self.p.post(f"{url}/terminer")
        r_cla = self.p.post(f"{url}/classer")
        self.assertEqual(r_cla.json()["code"], "TRANSITION_INTERDITE")

    def test_prestataire_ne_peut_pas_s_auto_valider_un_ajustement(self):
        demande = self.reserver().json()["id"]
        url = f"/api/demandes/{demande}"
        self.p.post(f"{url}/accepter")
        aj = self.p.post(f"{url}/ajustements", {"minutes": 30, "motif": "Cuisine"}, format="json").json()

        # Le prestataire tente de valider son propre ajustement
        r = self.p.post(f"/api/ajustements/{aj['id']}/repondre", {"accepte": True}, format="json")
        self.assertEqual(r.status_code, 403)

    def test_prestataire_ajustement_vide_refuse(self):
        demande = self.reserver().json()["id"]
        url = f"/api/demandes/{demande}"
        self.p.post(f"{url}/accepter")

        r = self.p.post(f"{url}/ajustements", {"minutes": 0, "produits": 0, "motif": "Rien"}, format="json")
        self.assertEqual(r.json()["code"], "AJUSTEMENT_VIDE")

    def test_identite_figee_empeche_modification_malveillante(self):
        # Le prestataire dépose une certification
        r_depot = self.p.post(
            "/api/moi/certification",
            {
                "recto": photo(), "verso": photo(), "selfie": photo(),
                "nom": "KAMGA", "prenoms": "Paul", "numero_document": "11223344",
                "mrz_presente": True, "mrz_valide": True,
                "consentement": True, "consentement_version": "v1",
                "consentement_texte": "Consentement...",
            },
            format="multipart",
        )
        self.assertEqual(r_depot.status_code, 201)

        # Tentative de changer nom ou de retirer un service -> IDENTITE_FIGEE
        r = self.p.patch("/api/moi/prestataire", {"nom": "AutreNom"}, format="json")
        self.assertEqual(r.json()["code"], "IDENTITE_FIGEE")
        r = self.p.patch("/api/moi/prestataire", {"prenom": "AutrePrenom"}, format="json")
        self.assertEqual(r.json()["code"], "IDENTITE_FIGEE")
        r = self.p.patch("/api/moi/prestataire", {"services": ["linge"]}, format="json")
        self.assertEqual(r.json()["code"], "IDENTITE_FIGEE")

        # Le téléphone est en lecture seule : il est ignoré et n'est pas modifié
        self.p.patch("/api/moi/prestataire", {"telephone": "+237699999999"}, format="json")
        self.assertEqual(Prestataire.objects.get(pk=self.presta.pk).telephone, "+237690000001")

        # Mais la disponibilité et la photo professionnelle restent modifiables
        r = self.p.patch("/api/moi/prestataire", {"en_ligne": False}, format="json")
        self.assertEqual(r.status_code, 200)

    # =========================================================================
    # 3. Isolation Croisée et Multi-Tenant
    # =========================================================================

    def test_tiers_ne_voit_ni_ne_modifie_les_demandes_d_autrui(self):
        demande = self.reserver().json()["id"]
        url = f"/api/demandes/{demande}"

        # Un client tiers ne peut ni lire, ni annuler, ni accepter
        self.assertEqual(self.c_tiers.get(url).status_code, 404)
        self.assertEqual(self.c_tiers.post(f"{url}/annuler").status_code, 403)
        self.assertEqual(self.c_tiers.post(f"{url}/accepter").status_code, 403)
        self.assertEqual(self.c_tiers.get("/api/demandes").json()["count"], 0)

        # Un prestataire tiers ne peut ni lire, ni accepter, ni refuser
        self.assertEqual(self.p_tiers.get(url).status_code, 404)
        self.assertEqual(self.p_tiers.post(f"{url}/accepter").status_code, 403)
        self.assertEqual(self.p_tiers.post(f"{url}/refuser", {"motif": "Vol"}).status_code, 403)
        self.assertEqual(self.p_tiers.get("/api/demandes").json()["count"], 0)

    def test_requetes_anonymes_bloquees(self):
        self.assertEqual(self.anonyme.get("/api/demandes").status_code, 401)
        self.assertEqual(self.anonyme.get("/api/moi").status_code, 401)
        self.assertEqual(self.anonyme.post("/api/demandes", {}).status_code, 401)
        self.assertEqual(self.anonyme.get("/api/signalements").status_code, 401)
