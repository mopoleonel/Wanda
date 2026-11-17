from django.test import SimpleTestCase, TestCase

from noyau.essais import client_de, creer_citoyen

from . import calcul
from .models import Tarif, tarifs_actuels
from .valeurs_depart import TARIFS_DEPART

DEPART = {}
for _s, _c, _v, _u, _l in TARIFS_DEPART:
    DEPART.setdefault(_s, {})[_c] = _v

# Les 8 cas de contrôle de 009_tarification.sql et de
# test/data/pricing/tarification_test.dart : les trois calculs doivent
# donner exactement les mêmes montants.
CAS = [
    ("menage", "ponctuelle", None,
     {"chambres": 2, "salons": 1, "cuisines": 1, "douche_wc": 1, "etat": "normal"},
     False, 175, 4500, 1, 4500),
    ("menage", "ponctuelle", None,
     {"chambres": 3, "salons": 1, "cuisines": 1, "douche_wc": 2, "vitres": True,
      "frigo": True, "four": False, "etat": "sale"},
     True, 357, 9700, 1, 9700),
    ("menage", "abonnement", "hebdomadaire",
     {"chambres": 1, "salons": 1, "cuisines": 1, "douche_wc": 1, "etat": "tres_sale"},
     False, 218, 5400, 4, 21600),
    ("linge", "ponctuelle", None,
     {"paniers": 2, "draps_delicats": True, "repassage": True, "pieces_repassage": 10},
     True, 150, 5000, 1, 5000),
    ("dechets", "abonnement", "hebdomadaire",
     {"sacs": 6, "passages_semaine": 2, "etage": 3, "distance_bac": "50"},
     False, 26, 1600, 8, 12800),
    ("dechets", "ponctuelle", None,
     {"sacs": 1, "etage": 0, "distance_bac": "10"},
     False, 15, 1300, 1, 1300),
    ("nuisibles", "ponctuelle", None,
     {"nuisible": "punaises", "pieces": 3, "infestation": "forte"},
     True, 60, 20200, 1, 20200),
    ("nuisibles", "abonnement", "mensuel",
     {"nuisible": "cafards", "pieces": 1, "infestation": "faible"},
     True, 20, 2900, 1, 2900),
]


class CalculPrix(SimpleTestCase):
    def test_huit_cas_communs_au_sql_et_au_dart(self):
        for service, formule, freq, rep, prod, minutes, passage, passages, total in CAS:
            with self.subTest(service=service, reponses=rep):
                r = calcul.calculer_prix(DEPART, service, formule, freq, rep, prod)
                self.assertEqual(
                    (r["minutes"], r["prix_passage"], r["passages"], r["prix_total"]),
                    (minutes, passage, passages, total),
                )

    def test_reponses_absentes_ou_invalides_comme_en_sql(self):
        # Texte au lieu d'un nombre : 0 ; booléen : 0 ; décimal tronqué.
        r = calcul.calculer_prix(DEPART, "menage", "ponctuelle", None,
                                 {"chambres": "2", "salons": True, "cuisines": 1.9}, False)
        self.assertEqual(r["minutes"], 45)
        # Distance numérique acceptée comme en SQL (« ->> » la met en texte).
        r = calcul.calculer_prix(DEPART, "dechets", "ponctuelle", None,
                                 {"sacs": 1, "distance_bac": 50}, False)
        self.assertEqual(r["minutes"], 15)
        with self.assertRaises(calcul.ServiceInconnu):
            calcul.calculer_prix(DEPART, "jardinage", "ponctuelle", None, {}, False)

    def test_remise_abonnement(self):
        tarifs = {**DEPART, "global": {**DEPART["global"], "remise_abonnement": 10}}
        r = calcul.calculer_prix(tarifs, *CAS[2][:5])
        # 5 400 × 4 × 90 % = 19 440 -> 19 500.
        self.assertEqual(r["prix_total"], 19500)

    def test_arrondis_postgres(self):
        self.assertEqual(calcul.arrondi("2.5"), 3)
        self.assertEqual(calcul._div(-7, 2), -3)
        self.assertEqual(calcul._centaine(0), 0)
        self.assertEqual(calcul._centaine(4401), 4500)

    def test_prix_d_un_ajustement(self):
        # 30 min à 1 200 FCFA/h = 600 ; + 500 de produits = 1 100.
        self.assertEqual(calcul.prix_ajustement(DEPART, 30, 500), 1100)
        self.assertEqual(calcul.prix_ajustement(DEPART, 45, 0), 900)


class TarifsEnBase(TestCase):
    def test_valeurs_de_depart_installees(self):
        self.assertEqual(Tarif.objects.count(), len(TARIFS_DEPART))
        self.assertEqual(tarifs_actuels(), DEPART)

    def test_un_tarif_modifie_change_le_prix(self):
        Tarif.objects.filter(service="global", cle="tarif_horaire").update(valeur=1300)
        client = client_de(creer_citoyen())
        r = client.post("/api/prix", {"service": "menage", "formule": "ponctuelle",
                                      "reponses": CAS[0][3]}, format="json")
        self.assertEqual(r.status_code, 200)
        # 175 min × 1 300 / 60 = 3 792 + 1 000 = 4 792 -> 4 800.
        self.assertEqual(r.json()["prix_total"], 4800)

    def test_api_tarifs_et_prix(self):
        client = client_de(creer_citoyen())
        self.assertEqual(client.get("/api/tarifs").json()["menage"]["chambre"], 30)
        r = client.post("/api/prix", {"service": "nuisibles", "formule": "ponctuelle",
                                      "reponses": CAS[6][3]}, format="json")
        # Produits anti-nuisibles toujours comptés, même sans les demander.
        self.assertEqual(r.json()["prix_total"], 20200)
        r = client.post("/api/prix", {"service": "menage", "formule": "abonnement"},
                        format="json")
        self.assertEqual(r.json()["code"], "FORMULE_INVALIDE")

    def test_connexion_obligatoire(self):
        self.assertEqual(client_de().get("/api/tarifs").status_code, 401)
