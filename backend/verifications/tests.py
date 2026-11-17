from django.contrib.auth import get_user_model

from comptes.models import Prestataire
from noyau.essais import EssaiAvecFichiers, client_de, creer_prestataire, photo
from notifications.models import Notification

from . import services
from .models import Verification


class Certification(EssaiAvecFichiers):
    def setUp(self):
        self.u = creer_prestataire(photo_pro="profils/x/profil/a.jpg")
        self.c = client_de(self.u)
        self.admin = get_user_model().objects.create_superuser("+237600000000", "motdepasse-admin")

    def deposer(self, client=None, numero="123456789"):
        return (client or self.c).post(
            "/api/moi/certification",
            {
                "recto": photo(), "verso": photo(), "selfie": photo(),
                "nom": "KAMGA", "prenoms": "Paul", "numero_document": numero,
                "mrz_presente": True, "mrz_valide": True,
                "consentement": True, "consentement_version": "v1",
                "consentement_texte": "J'accepte que WANDA conserve...",
            },
            format="multipart",
        )

    def test_profil_complet_exige(self):
        Prestataire.objects.filter(pk=self.u.pk).update(photo_pro="")
        self.c.force_authenticate(get_user_model().objects.get(pk=self.u.pk))
        self.assertEqual(self.deposer().json()["code"], "PROFIL_INCOMPLET")

    def test_depot_puis_validation_par_l_equipe(self):
        r = self.deposer()
        self.assertEqual(r.status_code, 201, r.content)
        self.assertEqual(r.json()["statut"], "en_attente")
        self.assertEqual(self.c.get("/api/moi/certification").json()["statut"], "en_attente")
        self.assertEqual(self.deposer().json()["code"], "CERTIFICATION_EN_COURS")

        # En cours d'examen : nom et prénom déjà figés.
        r = self.c.patch("/api/moi/prestataire", {"prenom": "Pierre"}, format="json")
        self.assertEqual(r.json()["code"], "IDENTITE_FIGEE")

        v = Verification.objects.get()
        self.assertTrue(v.recto.startswith("identites/{}/".format(self.u.pk)))
        services.decider(v, self.admin, True)
        self.assertTrue(Prestataire.objects.get(pk=self.u.pk).identite_verifiee)
        self.assertEqual(list(v.journal.values_list("action", flat=True)), ["creation", "valide"])
        self.assertTrue(Notification.objects.filter(destinataire=self.u,
                                                    titre="Identité vérifiée").exists())

    def test_rejet_puis_nouvelle_demande(self):
        self.deposer()
        services.decider(Verification.objects.get(), self.admin, False, "Selfie flou")
        self.assertFalse(Prestataire.objects.get(pk=self.u.pk).identite_verifiee)
        self.assertEqual(self.c.get("/api/moi/certification").json()["motif_rejet"], "Selfie flou")
        self.assertEqual(self.deposer().status_code, 201)

    def test_une_piece_pour_un_seul_compte(self):
        self.deposer()
        autre = client_de(creer_prestataire("+237690000077", photo_pro="profils/y/p/b.jpg"))
        self.assertEqual(self.deposer(autre).json()["code"], "DOCUMENT_DEJA_UTILISE")

    def test_pieces_d_identite_jamais_donnees_a_un_tiers(self):
        self.deposer()
        v = Verification.objects.get()
        autre = client_de(creer_prestataire("+237690000077"))
        r = autre.get("/api/photos/lien", {"chemin": v.selfie})
        self.assertEqual(r.status_code, 403)
        # L'équipe WANDA les voit dans l'administration.
        admin = client_de()
        admin.force_login(self.admin)
        self.assertEqual(admin.get("/admin/fichier", {"chemin": v.selfie}).status_code, 200)
        self.assertEqual(client_de().get("/admin/fichier", {"chemin": v.selfie}).status_code, 302)

    def test_consentement_obligatoire(self):
        r = self.c.post("/api/moi/certification",
                        {"recto": photo(), "verso": photo(), "selfie": photo(), "nom": "K",
                         "prenoms": "P", "consentement": False, "consentement_version": "v1",
                         "consentement_texte": "..."}, format="multipart")
        self.assertEqual(r.json()["code"], "CONSENTEMENT_REQUIS")
