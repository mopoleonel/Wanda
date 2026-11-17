from django.contrib import admin
from django.contrib.auth import get_user_model
from django.urls import reverse
from django.utils import timezone

from demandes.models import Ajustement
from demandes.services import changer_statut, creer_demande, demander_ajustement
from noyau.essais import EssaiAvecFichiers, client_de, creer_citoyen, creer_entreprise, creer_prestataire
from verifications.models import Verification


class Administration(EssaiAvecFichiers):
    """Chaque page de l'administration s'affiche (liste et fiche)."""

    def setUp(self):
        self.admin = get_user_model().objects.create_superuser("+237600000000", "motdepasse-admin")
        self.c = client_de()
        self.c.force_login(self.admin)

        presta = creer_prestataire()
        client = creer_citoyen()
        creer_entreprise()
        chemin = self.envoyer_photo(client_de(client))
        d = creer_demande(
            client, prestataire_id=presta.pk, service="menage", formule="ponctuelle",
            frequence="", reponses={"chambres": 1}, produits=False, photos=[chemin],
            analyse_id=None, date=timezone.localdate(), creneau="matin",
        )
        changer_statut(d.pk, presta, "accepte")
        demander_ajustement(d.pk, presta, minutes=30, produits=0, motif="Plus long", photos=[])
        Verification.objects.create(
            prestataire=presta.prestataire, nom="K", prenoms="P", recto="identites/x/a.jpg",
            verso="identites/x/b.jpg", selfie="identites/x/c.jpg", consentement_le=timezone.now(),
            consentement_version="v1", consentement_texte="...",
        )

    def test_listes_et_fiches(self):
        self.assertEqual(self.c.get("/admin/").status_code, 200)
        for modele, modele_admin in admin.site._registry.items():
            meta = modele._meta
            with self.subTest(modele=meta.label):
                liste = reverse("admin:{}_{}_changelist".format(meta.app_label, meta.model_name))
                self.assertEqual(self.c.get(liste).status_code, 200)
                objet = modele.objects.first()
                if objet is not None:
                    fiche = reverse("admin:{}_{}_change".format(meta.app_label, meta.model_name),
                                    args=[objet.pk])
                    self.assertEqual(self.c.get(fiche).status_code, 200)

    def test_decision_sur_une_verification(self):
        v = Verification.objects.get()
        url = reverse("admin:verifications_verification_change", args=[v.pk])
        r = self.c.post(url, {"decision": "valider", "motif_rejet": "",
                              "journal-TOTAL_FORMS": 0, "journal-INITIAL_FORMS": 0})
        self.assertEqual(r.status_code, 302, r.content[:500])
        v.refresh_from_db()
        self.assertEqual(v.statut, "valide")
        v.prestataire.refresh_from_db()
        self.assertTrue(v.prestataire.identite_verifiee)

    def test_tarif_modifiable_dans_la_liste(self):
        self.assertTrue(Ajustement.objects.exists())
        r = self.c.get("/admin/tarification/tarif/")
        self.assertContains(r, "Tarif horaire du prestataire")


class Sante(EssaiAvecFichiers):
    def test_sans_connexion(self):
        self.assertEqual(client_de().get("/api/sante").json(), {"statut": "ok"})


class SourceFactice:
    """Tables Supabase en mémoire, pour tester l'import sans base réelle."""

    def __init__(self, tables):
        self.tables = tables

    def existe(self, table):
        return table in self.tables

    def lignes(self, table):
        return [dict(r) for r in self.tables.get(table, [])]


class ImportSupabase(EssaiAvecFichiers):
    PRESTA = "11111111-1111-1111-1111-111111111111"
    CLIENT = "22222222-2222-2222-2222-222222222222"

    def source(self):
        import datetime as dt

        envoyee = dt.datetime(2026, 10, 24, 13, 56, tzinfo=dt.timezone.utc)
        return SourceFactice({
            "auth.users": [{"id": self.PRESTA, "phone": "237690000001"},
                           {"id": self.CLIENT, "phone": "237690000002"}],
            "public.particuliers": [{"id": self.PRESTA, "nom": "Essai", "prenom": "Testeur",
                                     "telephone": "690000001", "services": ["menage", "plombier"],
                                     "is_available": True}],
            "public.citoyens": [{"citoyen_id": self.CLIENT, "nom": "Client", "telephone": "+237690000002"}],
            "public.sollicitations": [{
                "id": "aaaaaaaa-0000-0000-0000-000000000001", "prestataire_id": self.PRESTA,
                "citoyen_id": self.CLIENT, "nom_citoyen": "Client", "numero_citoyen": "+237690000002",
                "date_sollicitation": envoyee, "statut": "termine", "service": "menage",
                "formule": "ponctuelle", "reponses": {"chambres": 1}, "prix_total": 2400,
                "prix_passage": 2400, "minutes_estimees": 70, "photos": [self.CLIENT + "/d/1.jpg"],
                "date_souhaitee": dt.date(2026, 10, 25), "creneau": "matin",
            }],
            "public.avis_prestataires": [
                {"sollicitation_id": "aaaaaaaa-0000-0000-0000-000000000001",
                 "prestataire_id": self.PRESTA, "citoyen_id": self.CLIENT, "note": 5},
                {"sollicitation_id": "aaaaaaaa-0000-0000-0000-000000000001",
                 "prestataire_id": self.PRESTA, "citoyen_id": self.CLIENT, "note": 1},
            ],
            "public.signalements": [{"id": 42, "type_probleme": "Fuite d'eau", "latitude": "4.05",
                                     "longitude": "9.7", "citoyen_id": self.CLIENT,
                                     "image_url": "https://x.supabase.co/a/b/photo%201.jpg"}],
        })

    def test_import_relancable_et_identifiants_conserves(self):
        from comptes.models import Prestataire, Utilisateur
        from demandes.models import Avis, Demande
        from noyau.import_supabase import Importeur
        from signalements.models import Signalement

        for _ in range(2):  # relancé : rien n'est dupliqué
            Importeur(SourceFactice(self.source().tables), ecrire=lambda *_: None).tout()
        self.assertEqual(Utilisateur.objects.count(), 2)
        self.assertEqual(Utilisateur.objects.get(pk=self.PRESTA).telephone, "+237690000001")
        p = Prestataire.objects.get(pk=self.PRESTA)
        self.assertEqual(p.services, ["menage"])  # ancien métier écarté
        self.assertEqual(p.telephone, "+237690000001")
        d = Demande.objects.get()
        self.assertEqual(d.date_sollicitation.hour, 13)
        self.assertEqual(d.photos, ["demandes/{}/d/1.jpg".format(self.CLIENT)])
        self.assertEqual(Avis.objects.get().note, 5)  # un seul avis par mission
        s = Signalement.objects.get()
        self.assertEqual(s.image, "signalements/{}/import/photo1.jpg".format(self.CLIENT))
        self.assertEqual(s.latitude, 4.05)
