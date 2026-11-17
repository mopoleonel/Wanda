from datetime import timedelta
from unittest import mock

from django.utils import timezone

from comptes.models import Citoyen, Prestataire
from noyau.essais import EssaiAvecFichiers, client_de, creer_citoyen, creer_prestataire
from notifications.models import Notification

from .models import AnalyseIA, Demande

MENAGE = {"chambres": 2, "salons": 1, "cuisines": 1, "douche_wc": 1, "etat": "normal"}


class Reservation(EssaiAvecFichiers):
    def setUp(self):
        self.presta = creer_prestataire()
        self.client_u = creer_citoyen()
        self.c = client_de(self.client_u)
        self.p = client_de(self.presta)

    def reserver(self, client=None, **champs):
        client = client or self.c
        donnees = {
            "prestataire": str(self.presta.pk),
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

    # ------------------------------------------------------------ création

    def test_prix_fixe_par_le_serveur(self):
        r = self.reserver(prix_total=100)  # champ ignoré : le prix vient du serveur
        self.assertEqual(r.status_code, 201, r.content)
        d = r.json()
        self.assertEqual((d["prix_total"], d["minutes_estimees"]), (4500, 175))
        self.assertEqual(d["statut"], "en_attente")
        self.assertEqual(d["client"]["telephone"], "+237690000002")
        self.assertEqual(d["prestataire"]["prenom"], "Paul")
        self.assertEqual(len(d["photos_liens"]), 1)
        self.assertEqual(len(d["numero"]), 6)
        # Le prestataire est prévenu.
        n = Notification.objects.get(destinataire=self.presta)
        self.assertEqual(n.titre, "Nouvelle demande : Ménage")
        self.assertIn("4 500 FCFA", n.corps)

    def test_nom_obligatoire(self):
        Citoyen.objects.filter(pk=self.client_u.pk).update(nom="")
        self.client_u.refresh_from_db()
        self.c.force_authenticate(type(self.client_u).objects.get(pk=self.client_u.pk))
        self.assertEqual(self.reserver().json()["code"], "PROFIL_CITOYEN_INCOMPLET")

    def test_prestataire_indisponible(self):
        Prestataire.objects.filter(pk=self.presta.pk).update(en_ligne=False)
        self.assertEqual(self.reserver().json()["code"], "PRESTATAIRE_INDISPONIBLE")
        Prestataire.objects.filter(pk=self.presta.pk).update(en_ligne=True)
        self.assertEqual(self.reserver(service="nuisibles").json()["code"],
                         "PRESTATAIRE_INDISPONIBLE")
        Prestataire.objects.filter(pk=self.presta.pk).update(
            abonnement_expire_le=timezone.now() - timedelta(minutes=1))
        self.assertEqual(self.reserver().json()["code"], "PRESTATAIRE_INDISPONIBLE")

    def test_photos_obligatoires_et_personnelles(self):
        self.assertEqual(self.reserver(photos=[]).json()["code"], "PHOTOS_REQUISES")
        autre = client_de(creer_citoyen("+237690000099", nom="Autre"))
        photo_d_un_autre = self.envoyer_photo(autre)
        self.assertEqual(self.reserver(photos=[photo_d_un_autre]).json()["code"],
                         "PHOTO_INVALIDE")
        self.assertEqual(
            self.reserver(photos=["demandes/{}/x/inventee.jpg".format(self.client_u.pk)])
            .json()["code"], "PHOTO_INVALIDE")

    def test_date_et_formule(self):
        hier = str(timezone.localdate() - timedelta(days=1))
        self.assertEqual(self.reserver(date_souhaitee=hier).json()["code"], "DATE_INVALIDE")
        self.assertEqual(self.reserver(formule="abonnement").json()["code"], "FORMULE_INVALIDE")
        r = self.reserver(formule="abonnement", frequence="hebdomadaire")
        self.assertEqual(r.json()["prix_total"], 4500 * 4)

    def test_un_prestataire_ne_reserve_pas(self):
        r = self.reserver(client=self.p)
        self.assertEqual(r.json()["code"], "CITOYEN_INCONNU")

    # ------------------------------------------------------------ statuts

    def test_parcours_complet(self):
        demande = self.reserver().json()["id"]
        url = "/api/demandes/" + demande

        # Le client ne peut pas accepter à la place du prestataire.
        self.assertEqual(self.c.post(url + "/accepter").json()["code"], "TRANSITION_INTERDITE")
        r = self.p.post(url + "/accepter")
        self.assertEqual(r.json()["statut"], "accepte")
        # Hors ligne pendant la mission.
        self.assertFalse(Prestataire.objects.get(pk=self.presta.pk).en_ligne)

        # Ajustement : +30 min = 600 FCFA.
        r = self.p.post(url + "/ajustements",
                        {"minutes": 30, "motif": "Cuisine très grasse"}, format="json")
        self.assertEqual(r.status_code, 201, r.content)
        aj = r.json()
        self.assertEqual(aj["prix_supp"], 600)
        self.assertEqual(self.c.get(url).json()["ajustement_en_attente"]["id"], aj["id"])
        # Un seul en attente à la fois.
        r = self.p.post(url + "/ajustements", {"minutes": 15, "motif": "Encore"}, format="json")
        self.assertEqual(r.json()["code"], "AJUSTEMENT_DEJA_EN_ATTENTE")
        # Seul le client répond.
        r = self.p.post("/api/ajustements/{}/repondre".format(aj["id"]), {"accepte": True},
                        format="json")
        self.assertEqual(r.status_code, 403)
        self.c.post("/api/ajustements/{}/repondre".format(aj["id"]), {"accepte": True},
                    format="json")
        d = self.c.get(url).json()
        self.assertEqual((d["prix_total"], d["minutes_estimees"]), (5100, 205))
        self.assertIsNone(d["ajustement_en_attente"])
        r = self.c.post("/api/ajustements/{}/repondre".format(aj["id"]), {"accepte": False},
                        format="json")
        self.assertEqual(r.json()["code"], "DEJA_REPONDU")

        # Fin de mission : de nouveau en ligne, date de fin enregistrée.
        self.assertEqual(self.p.post(url + "/terminer").json()["statut"], "termine")
        self.assertTrue(Prestataire.objects.get(pk=self.presta.pk).en_ligne)
        self.assertIsNotNone(Demande.objects.get(pk=demande).date_fin)
        # Plus d'annulation possible après la fin.
        self.assertEqual(self.c.post(url + "/annuler").json()["code"], "TRANSITION_INTERDITE")

        # Note puis classement.
        r = self.c.post(url + "/avis", {"note": 5, "commentaire": "Parfait"}, format="json")
        self.assertEqual(r.status_code, 201)
        self.assertEqual(self.c.post(url + "/avis", {"note": 4}, format="json").json()["code"],
                         "AVIS_DEJA_DONNE")
        self.assertEqual(self.c.post(url + "/classer").json()["statut"], "archive")
        presta = self.c.get("/api/prestataires/{}".format(self.presta.pk)).json()
        self.assertEqual((presta["note_moyenne"], presta["nb_avis"]), (5.0, 1))

        # Chaque étape a prévenu l'autre partie.
        titres = list(Notification.objects.filter(destinataire=self.client_u)
                      .order_by("cree_le").values_list("titre", flat=True))
        self.assertEqual(titres, ["Demande confirmée", "Ajustement demandé", "Service terminé"])

    def test_refus_avec_motif_et_annulation(self):
        d1 = self.reserver().json()["id"]
        r = self.p.post("/api/demandes/{}/refuser".format(d1), {"motif": "Pas dispo"},
                        format="json")
        self.assertEqual((r.json()["statut"], r.json()["motif_refus"]), ("refuse", "Pas dispo"))
        d2 = self.reserver().json()["id"]
        self.assertEqual(self.c.post("/api/demandes/{}/annuler".format(d2)).json()["statut"],
                         "annule")
        self.assertEqual(
            Notification.objects.filter(destinataire=self.presta, titre="Demande annulée").count(), 1)

    def test_demande_invisible_pour_les_autres(self):
        demande = self.reserver().json()["id"]
        intrus = client_de(creer_citoyen("+237690000099", nom="Intrus"))
        self.assertEqual(intrus.get("/api/demandes/" + demande).status_code, 404)
        self.assertEqual(intrus.post("/api/demandes/{}/annuler".format(demande)).status_code, 403)
        self.assertEqual(intrus.get("/api/demandes").json()["count"], 0)

    def test_suivi_depuis_une_date(self):
        demande = self.reserver().json()["id"]
        repere = (timezone.now() + timedelta(milliseconds=50)).isoformat()
        liste = self.p.get("/api/demandes", {"depuis": repere}).json()
        self.assertEqual(liste["count"], 0)
        repere = timezone.now().isoformat()
        self.p.post("/api/demandes/{}/accepter".format(demande))
        liste = self.c.get("/api/demandes", {"depuis": repere}).json()
        self.assertEqual([d["statut"] for d in liste["results"]], ["accepte"])

    # ---------------------------------------------------------- abonnement

    def test_passages_d_un_abonnement(self):
        ponctuelle = self.reserver().json()["id"]
        self.p.post("/api/demandes/{}/accepter".format(ponctuelle))
        r = self.p.post("/api/demandes/{}/passages".format(ponctuelle))
        self.assertEqual(r.json()["code"], "PASSAGE_IMPOSSIBLE")

        Prestataire.objects.filter(pk=self.presta.pk).update(en_ligne=True)
        abo = self.reserver(formule="abonnement", frequence="mensuel").json()["id"]
        url = "/api/demandes/{}/passages".format(abo)
        self.assertEqual(self.p.post(url).json()["code"], "PASSAGE_IMPOSSIBLE")
        self.p.post("/api/demandes/{}/accepter".format(abo))
        self.assertEqual(self.p.post(url).status_code, 201)
        self.assertEqual(self.p.post(url).json()["code"], "PASSAGE_DEJA_POINTE")
        self.assertEqual(self.c.get("/api/demandes/" + abo).json()["nb_passages"], 1)
        self.assertEqual(len(self.c.get(url).json()), 1)

    # ------------------------------------------------------------- photos

    def test_qui_voit_quelle_photo(self):
        demande = self.reserver().json()
        chemin = demande["photos"][0]
        lien = "/api/photos/lien"
        # Le client (auteur) et le prestataire de la demande : oui.
        self.assertEqual(self.c.get(lien, {"chemin": chemin}).status_code, 200)
        self.assertEqual(self.p.get(lien, {"chemin": chemin}).status_code, 200)
        # Un autre prestataire : non.
        autre = client_de(creer_prestataire("+237690000098"))
        self.assertEqual(autre.get(lien, {"chemin": chemin}).status_code, 403)

        # Photo d'ajustement : visible du client de la demande.
        self.p.post("/api/demandes/{}/accepter".format(demande["id"]))
        photo_aj = self.envoyer_photo(self.p, "ajustement")
        self.assertEqual(self.c.get(lien, {"chemin": photo_aj}).status_code, 403)
        self.p.post("/api/demandes/{}/ajustements".format(demande["id"]),
                    {"minutes": 30, "motif": "Pièce en plus", "photos": [photo_aj]}, format="json")
        r = self.c.get(lien, {"chemin": photo_aj})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(client_de().get(r.json()["url"]).status_code, 200)

    # -------------------------------------------------------------- IA

    def test_analyse_sans_cle_ne_bloque_pas(self):
        chemin = self.envoyer_photo(self.c)
        with mock.patch.dict("os.environ", {"GROQ_API_KEY": ""}):
            r = self.c.post("/api/demandes/analyse",
                            {"service": "menage", "reponses": MENAGE, "photos": [chemin]},
                            format="json")
        self.assertEqual(r.status_code, 200)
        self.assertEqual((r.json()["resultat"], r.json()["erreur"]), (None, "configuration"))

    def test_analyse_enregistree_et_jointe_a_la_demande(self):
        chemin = self.envoyer_photo(self.c)
        reponse_ia = (
            '{"photos_conformes": true, "estimation": {"quantite_min": 3, "niveau": "sale",'
            ' "nuisible": "dragons"}, "confiance": 1.7, "incoherences": ["Plus sale", 4]}'
        )
        with mock.patch.dict("os.environ", {"GROQ_API_KEY": "cle-test"}), \
                mock.patch("demandes.ia.appeler_groq", return_value=reponse_ia):
            r = self.c.post("/api/demandes/analyse",
                            {"service": "menage", "reponses": MENAGE, "photos": [chemin]},
                            format="json")
        resultat = r.json()["resultat"]
        # Valeurs nettoyées : nuisible inconnu retiré, confiance bornée.
        self.assertEqual(resultat["estimation"]["niveau"], "sale")
        self.assertIsNone(resultat["estimation"]["nuisible"])
        self.assertEqual(resultat["confiance"], 1.0)
        self.assertEqual(resultat["incoherences"], ["Plus sale"])
        d = self.reserver(analyse=r.json()["analyse_id"], photos=[chemin]).json()
        self.assertEqual(d["ia_analyse"]["estimation"]["niveau"], "sale")
        self.assertEqual(AnalyseIA.objects.count(), 1)

    def test_analyse_des_photos_d_un_autre_refusee(self):
        autre = client_de(creer_citoyen("+237690000099", nom="Autre"))
        chemin = self.envoyer_photo(autre)
        r = self.c.post("/api/demandes/analyse",
                        {"service": "menage", "photos": [chemin]}, format="json")
        self.assertEqual(r.status_code, 403)
