"""Outils communs aux tests (comptes, photos, client API connecté)."""
import shutil
import tempfile
from datetime import timedelta

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient

from comptes.models import Citoyen, Entreprise, Prestataire, Utilisateur

# Plus petit JPEG valide (1 × 1 pixel).
JPEG = bytes.fromhex(
    "ffd8ffe000104a46494600010100000100010000ffdb004300080606070605080707070909080a0c"
    "140d0c0b0b0c1912130f141d1a1f1e1d1a1c1c20242e2720222c231c1c2837292c30313434341f27"
    "393d38323c2e333432ffc0000b080001000101011100ffc4001f000001050101010101010000000000"
    "0000000102030405060708090a0bffc400b5100002010303020403050504040000017d0102030004"
    "1105122131410613516107227114328191a1082342b1c11552d1f02433627282090a161718191a25"
    "262728292a3435363738393a434445464748494a535455565758595a636465666768696a73747576"
    "7778797a838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2"
    "c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae1e2e3e4e5e6e7e8e9eaf1f2f3f4f5f6f7f8f9faffda0008"
    "010100003f00fbd3ffd9"
)


def photo(nom="photo.jpg", contenu=JPEG):
    return SimpleUploadedFile(nom, contenu, content_type="image/jpeg")


def creer_citoyen(telephone="+237690000002", nom="Mbarga", prenom="Lucie"):
    u = Utilisateur.objects.create_user(telephone, type_compte="citoyen")
    Citoyen.objects.create(utilisateur=u, telephone=telephone, nom=nom, prenom=prenom)
    return u


def creer_prestataire(telephone="+237690000001", services=("menage", "linge"),
                      en_ligne=True, abonne=True, **champs):
    u = Utilisateur.objects.create_user(telephone, type_compte="particulier")
    Prestataire.objects.create(
        utilisateur=u, telephone=telephone, nom=champs.pop("nom", "Kamga"),
        prenom=champs.pop("prenom", "Paul"), services=list(services), en_ligne=en_ligne,
        abonnement_expire_le=timezone.now() + timedelta(days=10) if abonne else None,
        type_abonnement="ESSAI" if abonne else "", **champs,
    )
    return u


def creer_entreprise(telephone="+237690000003", secteur="Hydraulique (Fuites d'eau, etc.)"):
    u = Utilisateur.objects.create_user(telephone, type_compte="entreprise")
    Entreprise.objects.create(
        utilisateur=u, telephone=telephone, nom_entreprise="Eau Pro", secteur_activite=secteur
    )
    return u


def client_de(utilisateur=None):
    c = APIClient()
    if utilisateur is not None:
        c.force_authenticate(utilisateur)
    return c


class EssaiAvecFichiers(TestCase):
    """Les fichiers des tests vont dans un dossier temporaire, effacé ensuite."""

    @classmethod
    def setUpClass(cls):
        cls._media = tempfile.mkdtemp(prefix="wanda-tests-")
        cls._reglage = override_settings(MEDIA_ROOT=cls._media)
        cls._reglage.enable()
        super().setUpClass()

    @classmethod
    def tearDownClass(cls):
        super().tearDownClass()
        cls._reglage.disable()
        shutil.rmtree(cls._media, ignore_errors=True)

    def envoyer_photo(self, client, dossier="demande"):
        r = client.post("/api/photos", {"fichier": photo(), "dossier": dossier}, format="multipart")
        self.assertEqual(r.status_code, 201, r.content)
        return r.json()["chemin"]
