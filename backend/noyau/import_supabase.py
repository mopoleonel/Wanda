"""Import des données de Supabase dans le back-end Django.

Les identifiants (UUID) sont conservés : un compte, une demande ou une
vérification garde le même identifiant des deux côtés. L'import est
relançable : une ligne déjà importée est mise à jour, jamais dupliquée.

Source : la base PostgreSQL de Supabase (lecture seule). Les fichiers
(photos, pièces d'identité) peuvent être copiés en plus depuis Supabase
Storage avec la clé « service_role ».

Correspondance des chemins de fichiers :
  bucket « demandes »   <uid>/...      -> demandes/<uid>/...
  bucket « identites »  <uid>/...      -> identites/<uid>/...
  URL publique (photos de profil, logos, signalements)
                                        -> profils|signalements/<uid>/import/<nom>
"""
import json
import logging
import urllib.parse
import urllib.request
import uuid
from datetime import date, datetime

from django.core.files.base import ContentFile
from django.core.files.storage import FileSystemStorage
from django.conf import settings
from django.db import transaction

from comptes.models import (
    CODES_SERVICES, AppareilPush, Citoyen, Entreprise, Prestataire, Utilisateur,
)
from demandes.models import AnalyseIA, Ajustement, Avis, Demande, Passage
from signalements.models import Signalement
from tarification.models import Tarif
from verifications.models import JournalVerification, Verification

from .telephone import normaliser

journal = logging.getLogger("wanda.import")

_ESPACE_NOMS = uuid.UUID("5b0e2a8c-3a6f-4f43-9e55-7f1c2d0a9b11")


def _uuid(valeur):
    """UUID d'origine, ou UUID stable dérivé d'un identifiant numérique."""
    try:
        return uuid.UUID(str(valeur))
    except ValueError:
        return uuid.uuid5(_ESPACE_NOMS, str(valeur))


def _ids(modele):
    """Identifiants existants, en texte (la source peut donner des UUID ou du
    texte selon le pilote)."""
    return {str(pk) for pk in modele.objects.values_list("pk", flat=True)}


def _s(v):
    return None if v is None else str(v)


def _texte(v, longueur=None):
    t = "" if v is None else str(v).strip()
    return t[:longueur] if longueur else t


def _liste(v):
    if v is None:
        return []
    if isinstance(v, str):  # « {a,b} » si la source renvoie du texte
        return [x for x in v.strip("{}").split(",") if x]
    return list(v)


def _json(v, defaut):
    if v is None:
        return defaut
    if isinstance(v, str):
        try:
            return json.loads(v)
        except ValueError:
            return defaut
    return v


def _jour(v):
    if isinstance(v, datetime):
        return v.date()
    if isinstance(v, date):
        return v
    return None


class SourcePostgres:
    """Lecture de la base Supabase (psycopg2)."""

    def __init__(self, url):
        import psycopg2
        import psycopg2.extras

        self._cnx = psycopg2.connect(url)
        self._cnx.set_session(readonly=True)
        self._extras = psycopg2.extras

    def existe(self, table):
        with self._cnx.cursor() as c:
            c.execute("select to_regclass(%s)", [table])
            return c.fetchone()[0] is not None

    def colonnes(self, table):
        schema, nom = table.split(".")
        with self._cnx.cursor() as c:
            c.execute(
                "select column_name from information_schema.columns "
                "where table_schema = %s and table_name = %s", [schema, nom])
            return {r[0] for r in c.fetchall()}

    def lignes(self, table):
        with self._cnx.cursor(cursor_factory=self._extras.RealDictCursor) as c:
            c.execute("select * from {}".format(table))
            return [dict(r) for r in c.fetchall()]


class Fichiers:
    """Copie des fichiers depuis Supabase Storage (facultatif)."""

    def __init__(self, url_supabase=None, cle_service=None):
        self.url = (url_supabase or "").rstrip("/")
        self.cle = cle_service or ""
        self.actif = bool(self.url and self.cle)
        self.copies = 0
        self.echecs = []
        self._stockage = FileSystemStorage(location=settings.MEDIA_ROOT)

    def _telecharger(self, url, avec_cle):
        entetes = {"Authorization": "Bearer " + self.cle} if avec_cle else {}
        with urllib.request.urlopen(urllib.request.Request(url, headers=entetes), timeout=30) as r:
            return r.read()

    def _enregistrer(self, chemin, url, avec_cle):
        if not self.actif or self._stockage.exists(chemin):
            return
        try:
            contenu = self._telecharger(url, avec_cle)
        except Exception as exc:  # réseau, 404… : on note et on continue
            self.echecs.append("{} ({})".format(chemin, exc))
            return
        self._stockage.save(chemin, ContentFile(contenu))
        self.copies += 1

    def objet(self, bucket, chemin_source):
        """Fichier d'un bucket privé -> chemin local."""
        if not chemin_source:
            return ""
        chemin = "{}/{}".format(bucket, chemin_source.lstrip("/"))
        url = "{}/storage/v1/object/{}/{}".format(
            self.url, bucket, urllib.parse.quote(chemin_source.lstrip("/")))
        self._enregistrer(chemin, url, True)
        return chemin

    def public(self, url, espace, proprietaire):
        """Fichier désigné par une URL publique -> chemin local."""
        if not url:
            return ""
        if not url.startswith("http"):
            return url  # déjà un chemin
        nom = urllib.parse.unquote(urllib.parse.urlparse(url).path.rsplit("/", 1)[-1]) or "fichier.jpg"
        nom = "".join(c for c in nom if c.isalnum() or c in "-_.")[:80] or "fichier.jpg"
        chemin = "{}/{}/import/{}".format(espace, proprietaire, nom)
        self._enregistrer(chemin, url, False)
        return chemin


class Importeur:
    def __init__(self, source, fichiers=None, ecrire=print):
        self.src = source
        self.fichiers = fichiers or Fichiers()
        self.ecrire = ecrire
        self.bilan = {}

    def _compter(self, cle, n=1):
        self.bilan[cle] = self.bilan.get(cle, 0) + n

    def _table(self, nom):
        return self.src.lignes(nom) if self.src.existe(nom) else []

    # ------------------------------------------------------------- comptes

    def comptes(self):
        types = {_s(r["id"]): r.get("user_type") for r in self._table("public.profiles")}
        citoyens = {_s(r["citoyen_id"]): r for r in self._table("public.citoyens")}
        prestataires = {_s(r["id"]): r for r in self._table("public.particuliers")}
        entreprises = {_s(r["id"]): r for r in self._table("public.entreprises")}
        deja = set()
        for u in self._table("auth.users"):
            uid = _s(u["id"])
            profil = citoyens.get(uid) or prestataires.get(uid) or entreprises.get(uid) or {}
            telephone = normaliser("+" + str(u.get("phone") or "").lstrip("+")) if u.get("phone") \
                else normaliser(_texte(profil.get("telephone")))
            actif = True
            if telephone is None or telephone in deja:
                # Ancien compte sans numéro (ou numéro en double) : gardé pour
                # l'historique, mais inutilisable pour se connecter.
                telephone, actif = "sans-" + str(uid).replace("-", "")[:12], False
                self._compter("comptes sans numéro (désactivés)")
            deja.add(telephone)
            type_compte = types.get(uid) or (
                "citoyen" if uid in citoyens else
                "particulier" if uid in prestataires else
                "entreprise" if uid in entreprises else ""
            )
            Utilisateur.objects.update_or_create(
                pk=uid, defaults={"telephone": telephone, "type_compte": type_compte or "",
                                  "is_active": actif},
            )
            self._compter("comptes")

        for uid, c in citoyens.items():
            Citoyen.objects.update_or_create(utilisateur_id=uid, defaults={
                "nom": _texte(c.get("nom"), 100), "prenom": _texte(c.get("prenom"), 100),
                "email": _texte(c.get("email"), 254),
                "telephone": normaliser(_texte(c.get("telephone"))) or _texte(c.get("telephone"), 20),
                "photo": self.fichiers.public(c.get("photo_url"), "profils", uid),
            })
            self._compter("citoyens")

        for uid, p in prestataires.items():
            services = [s for s in _liste(p.get("services")) if s in CODES_SERVICES]
            Prestataire.objects.update_or_create(utilisateur_id=uid, defaults={
                "nom": _texte(p.get("nom"), 100), "prenom": _texte(p.get("prenom"), 100),
                "telephone": normaliser(_texte(p.get("telephone"))) or _texte(p.get("telephone"), 20),
                "services": services,
                "photo_pro": self.fichiers.public(p.get("photo_pro_url"), "profils", uid),
                "en_ligne": bool(p.get("is_available")),
                "latitude": p.get("latitude"), "longitude": p.get("longitude"),
                "abonnement_expire_le": p.get("abonnement_expire_at"),
                "type_abonnement": _texte(p.get("type_abonnement"), 30),
                "essai_utilise": bool(p.get("essai_utilise")),
                "identite_verifiee": bool(p.get("identite_verifiee")),
            })
            self._compter("prestataires")

        for uid, e in entreprises.items():
            Entreprise.objects.update_or_create(utilisateur_id=uid, defaults={
                "nom_entreprise": _texte(e.get("nom_entreprise"), 150) or "Entreprise",
                "secteur_activite": _texte(e.get("secteur_activite"), 100),
                "telephone": normaliser(_texte(e.get("telephone"))) or _texte(e.get("telephone"), 20),
                "logo": self.fichiers.public(e.get("logo_url"), "profils", uid),
            })
            self._compter("entreprises")

        for t in self._table("public.device_tokens"):
            if Utilisateur.objects.filter(pk=t["user_id"]).exists():
                AppareilPush.objects.update_or_create(fcm_token=t["fcm_token"], defaults={
                    "utilisateur_id": t["user_id"], "plateforme": _texte(t.get("platform"), 20) or "android",
                })
                self._compter("appareils")

    # ------------------------------------------------------------- tarifs

    def tarifs(self):
        for t in self._table("public.tarifs"):
            Tarif.objects.update_or_create(service=t["service"], cle=t["cle"], defaults={
                "valeur": t["valeur"], "unite": t["unite"], "libelle": _texte(t.get("libelle"), 200),
            })
            self._compter("tarifs")

    # ------------------------------------------------------------- demandes

    def demandes(self):
        citoyens = _ids(Citoyen)
        prestataires = _ids(Prestataire)
        for s in self._table("public.sollicitations"):
            if _s(s.get("citoyen_id")) not in citoyens or _s(s.get("prestataire_id")) not in prestataires:
                self._compter("demandes ignorées (client ou prestataire inconnu)")
                continue
            service = s.get("service") or ""
            if not service:
                # Mission d'avant les services ménagers : gardée pour
                # l'historique et les avis, sans prix.
                self._compter("anciennes missions (sans service)")
            envoyee = s.get("date_sollicitation")
            formule = s.get("formule") or "ponctuelle"
            Demande.objects.update_or_create(pk=s["id"], defaults={
                "prestataire_id": s["prestataire_id"], "citoyen_id": s["citoyen_id"],
                "nom_citoyen": _texte(s.get("nom_citoyen"), 100),
                "prenom_citoyen": _texte(s.get("prenom_citoyen"), 100),
                "numero_citoyen": _texte(s.get("numero_citoyen"), 20),
                "statut": s.get("statut") or "en_attente",
                "date_fin": s.get("date_fin"),
                "service": service,
                "formule": formule,
                "frequence": _texte(s.get("frequence")) if formule == "abonnement" else "",
                "reponses": _json(s.get("reponses"), {}),
                "produits_fournis": bool(s.get("produits_fournis")),
                "minutes_estimees": s.get("minutes_estimees") or 0,
                "prix_passage": s.get("prix_passage") or 0,
                "prix_total": s.get("prix_total") or 0,
                "prix_detail": _json(s.get("prix_detail"), {}),
                "photos": [self.fichiers.objet("demandes", p) for p in _liste(s.get("photos"))],
                "ia_analyse": _json(s.get("ia_analyse"), None),
                "date_souhaitee": s.get("date_souhaitee") or _jour(envoyee) or date.today(),
                "creneau": s.get("creneau") or "matin",
                "motif_refus": _texte(s.get("motif_refus"), 200),
            })
            if envoyee:
                # auto_now_add : on remet la vraie date d'envoi.
                Demande.objects.filter(pk=s["id"]).update(date_sollicitation=envoyee)
            self._compter("demandes")

        demandes = _ids(Demande)
        for a in self._table("public.ajustements"):
            if _s(a["sollicitation_id"]) not in demandes:
                continue
            Ajustement.objects.update_or_create(pk=a["id"], defaults={
                "demande_id": a["sollicitation_id"],
                "minutes_supp": a.get("minutes_supp") or 0,
                "produits_supp": a.get("produits_supp") or 0,
                "motif": _texte(a.get("motif"), 500),
                "photos": [self.fichiers.objet("demandes", p) for p in _liste(a.get("photos"))],
                "prix_supp": a.get("prix_supp") or 0,
                "statut": a.get("statut") or "en_attente",
                "repondu_le": a.get("repondu_at"),
            })
            if a.get("created_at"):
                Ajustement.objects.filter(pk=a["id"]).update(cree_le=a["created_at"])
            self._compter("ajustements")

        for p in self._table("public.passages"):
            if _s(p["sollicitation_id"]) not in demandes:
                continue
            jour = _jour(p.get("effectue_le")) or date.today()
            if Passage.objects.filter(demande_id=p["sollicitation_id"], jour=jour).exclude(pk=p["id"]).exists():
                continue
            Passage.objects.update_or_create(pk=p["id"], defaults={
                "demande_id": p["sollicitation_id"], "jour": jour,
            })
            Passage.objects.filter(pk=p["id"]).update(effectue_le=p.get("effectue_le"))
            self._compter("passages")

        for a in self._table("public.avis_prestataires"):
            if _s(a.get("sollicitation_id")) not in demandes or not 1 <= (a.get("note") or 0) <= 5:
                continue
            if Avis.objects.filter(demande_id=a["sollicitation_id"]).exists():
                continue  # un seul avis par mission
            avis = Avis.objects.create(
                demande_id=a["sollicitation_id"], prestataire_id=a["prestataire_id"],
                citoyen_id=a["citoyen_id"], note=a["note"],
                commentaire=_texte(a.get("commentaire"), 500),
            )
            if a.get("created_at"):
                Avis.objects.filter(pk=avis.pk).update(cree_le=a["created_at"])
            self._compter("avis")

        for a in self._table("public.analyses_ia"):
            if _s(a.get("citoyen_id")) not in citoyens:
                continue
            AnalyseIA.objects.update_or_create(pk=a["id"], defaults={
                "citoyen_id": a["citoyen_id"], "service": a.get("service") or "",
                "reponses": _json(a.get("reponses"), {}),
                "photos": [self.fichiers.objet("demandes", p) for p in _liste(a.get("photos"))],
                "resultat": _json(a.get("resultat"), None),
                "erreur": _texte(a.get("erreur"), 100), "modele": _texte(a.get("modele"), 100),
            })
            self._compter("analyses IA")

    # -------------------------------------------------------- vérifications

    def verifications(self):
        prestataires = _ids(Prestataire)
        for v in self._table("public.prestataire_verifications"):
            if _s(v["prestataire_id"]) not in prestataires:
                continue
            verifie_par = v.get("verifie_par")
            if verifie_par and not Utilisateur.objects.filter(pk=verifie_par).exists():
                verifie_par = None
            Verification.objects.update_or_create(pk=v["id"], defaults={
                "prestataire_id": v["prestataire_id"],
                "type_document": _texte(v.get("type_document"), 20) or "CNI_CM",
                "numero_document": _texte(v.get("numero_document"), 50),
                "nom": _texte(v.get("nom"), 100), "prenoms": _texte(v.get("prenoms"), 150),
                "date_naissance": v.get("date_naissance"),
                "lieu_naissance": _texte(v.get("lieu_naissance"), 100),
                "sexe": _texte(v.get("sexe"), 1), "date_expiration": v.get("date_expiration"),
                "mrz_presente": bool(v.get("mrz_presente")), "mrz_valide": bool(v.get("mrz_valide")),
                "saisie_corrigee": bool(v.get("saisie_corrigee")),
                "recto": self.fichiers.objet("identites", v.get("recto_path")),
                "verso": self.fichiers.objet("identites", v.get("verso_path")),
                "selfie": self.fichiers.objet("identites", v.get("selfie_path")),
                "consentement_le": v.get("consentement_at"),
                "consentement_version": _texte(v.get("consentement_version"), 20),
                "consentement_texte": _texte(v.get("consentement_texte")),
                "statut": v.get("statut") or "en_attente",
                "motif_rejet": _texte(v.get("motif_rejet"), 300),
                "verifie_par_id": verifie_par, "verifie_le": v.get("verifie_at"),
            })
            if v.get("created_at"):
                Verification.objects.filter(pk=v["id"]).update(cree_le=v["created_at"])
            self._compter("vérifications d'identité")

        verifications = _ids(Verification)
        JournalVerification.objects.filter(verification_id__in=verifications).delete()
        for j in self._table("public.prestataire_verifications_journal"):
            if _s(j["verification_id"]) not in verifications:
                continue
            acteur = j.get("acteur")
            entree = JournalVerification.objects.create(
                verification_id=j["verification_id"], action=_texte(j.get("action"), 30),
                ancien_statut=_texte(j.get("ancien_statut"), 20),
                nouveau_statut=_texte(j.get("nouveau_statut"), 20),
                acteur_id=acteur if acteur and Utilisateur.objects.filter(pk=acteur).exists() else None,
                details=_texte(j.get("details"), 300),
            )
            if j.get("at"):
                JournalVerification.objects.filter(pk=entree.pk).update(le=j["at"])

    # --------------------------------------------------------- signalements

    def signalements(self):
        citoyens = _ids(Citoyen)
        entreprises = _ids(Entreprise)
        for s in self._table("public.signalements"):
            pk = _uuid(s["id"])
            citoyen = s.get("citoyen_id") if _s(s.get("citoyen_id")) in citoyens else None
            Signalement.objects.update_or_create(pk=pk, defaults={
                "type_probleme": _texte(s.get("type_probleme"), 100),
                "image": self.fichiers.public(s.get("image_url"), "signalements", citoyen or "anonyme"),
                "latitude": float(s.get("latitude") or 0), "longitude": float(s.get("longitude") or 0),
                "entreprise_id": s.get("entreprise_id") if _s(s.get("entreprise_id")) in entreprises else None,
                "citoyen_id": citoyen,
                "statut": s.get("statut") or "en_attente",
                "ia_validation_details": _texte(s.get("ia_validation_details"), 500),
            })
            if s.get("created_at"):
                Signalement.objects.filter(pk=pk).update(cree_le=s["created_at"])
            self._compter("signalements")

    def tout(self):
        with transaction.atomic():
            self.comptes()
            self.tarifs()
            self.demandes()
            self.verifications()
            self.signalements()
        if self.fichiers.actif:
            self._compter("fichiers copiés", self.fichiers.copies)
        return self.bilan
