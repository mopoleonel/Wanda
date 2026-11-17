"""Attribution d'un signalement au secteur d'entreprise compétent.

Copie de lib/data/models/secteur.dart : types de l'écran reconnus tels
quels, types libres (renvoyés par l'IA) classés par mots-clés, sinon
« Sécurité Publique » plutôt que de n'arriver chez personne.
"""
import re
import unicodedata

HYDRAULIQUE = "Hydraulique (Fuites d'eau, etc.)"
ELECTRICITE = "Électricité (Pannes, Poteaux, etc.)"
VOIRIE = "BTP / Voirie (Nids de poule, etc.)"
ENVIRONNEMENT = "Environnement (Déchets, etc.)"
SECURITE = "Sécurité Publique"

SECTEURS = [HYDRAULIQUE, ELECTRICITE, VOIRIE, ENVIRONNEMENT, SECURITE]

TYPES_CONNUS = {
    "Fuite d'eau": HYDRAULIQUE,
    "Électricité": ELECTRICITE,
    "Dépôt d'ordures": ENVIRONNEMENT,
    "BTP / Voirie": VOIRIE,
    "Sécurité Publique": SECURITE,
    "Autre (IA)": SECURITE,
}

MOTS_CLES = {
    HYDRAULIQUE: ["eau", "fuite", "canalisation", "inondation", "egout", "caniveau",
                  "tuyau", "robinet", "borne fontaine", "assainissement"],
    ELECTRICITE: ["electri", "poteau", "cable", "fil", "panne", "lampadaire",
                  "eclairage", "transformateur", "courant"],
    ENVIRONNEMENT: ["ordure", "dechet", "poubelle", "detritus", "decharge",
                    "plastique", "salete", "insalubr"],
    VOIRIE: ["route", "nid de poule", "nids de poule", "voirie", "chaussee",
             "trottoir", "pont", "goudron", "bitume", "effondr", "fissure",
             "chantier", "batiment"],
}


def _sans_accents(texte):
    decompose = unicodedata.normalize("NFD", texte.lower())
    return "".join(c for c in decompose if unicodedata.category(c) != "Mn")


def secteur_pour_type(type_probleme):
    connu = TYPES_CONNUS.get((type_probleme or "").strip())
    if connu:
        return connu
    t = _sans_accents(type_probleme or "")
    for secteur, mots in MOTS_CLES.items():
        # En début de mot : « eau » ne doit pas reconnaître « réseau ».
        if any(re.search(r"\b" + re.escape(m), t) for m in mots):
            return secteur
    return SECURITE


def types_du_secteur(secteur):
    types = [t for t, s in TYPES_CONNUS.items() if s == secteur]
    return types or [secteur]
