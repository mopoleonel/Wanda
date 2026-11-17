from django.test import SimpleTestCase

from noyau.essais import EssaiAvecFichiers, client_de, creer_citoyen, creer_entreprise, photo
from notifications.models import Notification

from .models import Signalement
from .secteurs import ELECTRICITE, ENVIRONNEMENT, HYDRAULIQUE, SECURITE, VOIRIE, secteur_pour_type


class Secteurs(SimpleTestCase):
    def test_comme_dans_l_app(self):
        self.assertEqual(secteur_pour_type("Fuite d'eau"), HYDRAULIQUE)
        self.assertEqual(secteur_pour_type("Nid de poule"), VOIRIE)
        self.assertEqual(secteur_pour_type("Câble arraché"), ELECTRICITE)
        self.assertEqual(secteur_pour_type("Tas de déchets"), ENVIRONNEMENT)
        # « eau » ne reconnaît pas « réseau ».
        self.assertEqual(secteur_pour_type("Réseau mobile coupé"), SECURITE)
        self.assertEqual(secteur_pour_type("Autre (IA)"), SECURITE)


class Signalements(EssaiAvecFichiers):
    def test_transmis_a_l_entreprise_du_secteur(self):
        entreprise = creer_entreprise()
        citoyen = client_de(creer_citoyen())
        r = citoyen.post("/api/signalements",
                         {"image": photo(), "type_probleme": "Fuite d'eau",
                          "latitude": 4.05, "longitude": 9.7}, format="multipart")
        self.assertEqual(r.status_code, 201, r.content)
        self.assertEqual(r.json()["entreprise"], str(entreprise.pk))
        self.assertTrue(Notification.objects.filter(destinataire=entreprise).exists())

        e = client_de(entreprise)
        missions = e.get("/api/signalements").json()["results"]
        self.assertEqual(len(missions), 1)
        url = "/api/signalements/{}/statut".format(missions[0]["id"])
        self.assertEqual(e.post(url, {"statut": "resolu"}, format="json").json()["code"],
                         "TRANSITION_INTERDITE")
        self.assertEqual(e.post(url, {"statut": "en_cours"}, format="json").json()["statut"],
                         "en_cours")
        self.assertEqual(e.post(url, {"statut": "resolu"}, format="json").json()["statut"],
                         "resolu")
        self.assertEqual(citoyen.get("/api/signalements").json()["results"][0]["statut"],
                         "resolu")

    def test_une_entreprise_ne_voit_pas_les_autres_secteurs(self):
        creer_entreprise()  # hydraulique
        autre = client_de(creer_entreprise("+237690000004", secteur=VOIRIE))
        citoyen = client_de(creer_citoyen())
        citoyen.post("/api/signalements", {"image": photo(), "type_probleme": "Fuite d'eau",
                                           "latitude": 4, "longitude": 9}, format="multipart")
        self.assertEqual(autre.get("/api/signalements").json()["count"], 0)
        sig = Signalement.objects.get()
        r = autre.post("/api/signalements/{}/statut".format(sig.pk), {"statut": "en_cours"},
                       format="json")
        self.assertEqual(r.status_code, 404)

    def test_seul_un_citoyen_signale(self):
        e = client_de(creer_entreprise())
        r = e.post("/api/signalements", {"image": photo(), "type_probleme": "x",
                                         "latitude": 4, "longitude": 9}, format="multipart")
        self.assertEqual(r.status_code, 403)
