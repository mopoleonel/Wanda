"""Analyse des photos d'une demande par l'IA (Groq, modèle de vision).

Portage de l'Edge Function analyze-demande-menage :
  * la clé GROQ_API_KEY reste sur le serveur ;
  * seules les photos de l'utilisateur lui-même sont envoyées ;
  * le résultat est enregistré (AnalyseIA) puis renvoyé ;
  * l'IA ne bloque jamais une réservation : en cas d'échec, le résultat est
    vide et le prix est calculé sur le questionnaire seul.
"""
import base64
import json
import os
import urllib.error
import urllib.request

from noyau import stockage

from .models import AnalyseIA

MODELE_PAR_DEFAUT = "qwen/qwen3.8-27b"
MAX_OCTETS = 4 * 1024 * 1024
DELAI = 25

CONSIGNES = {
    "menage": "Service : ménage à domicile. Estime l'ÉTAT du logement visible : "
    '"normal" (entretien courant), "sale" (pas nettoyé depuis un moment) ou '
    '"tres_sale" (après travaux, déménagement, longue absence). Donne-le dans '
    "estimation.niveau. quantite_min / quantite_max : nombre de pièces visibles "
    "si tu peux l'estimer, sinon null.",
    "linge": "Service : lessive et repassage. Estime la QUANTITÉ de linge en "
    "PANIERS standards (environ 5 kg chacun) : estimation.quantite_min et "
    "estimation.quantite_max. estimation.niveau : null.",
    "dechets": "Service : ramassage des poubelles à domicile. Estime le NOMBRE "
    "DE SACS de 50 litres visibles : estimation.quantite_min et "
    "estimation.quantite_max. estimation.niveau : null.",
    "nuisibles": "Service : désinsectisation / dératisation. Identifie le "
    'nuisible (estimation.nuisible parmi "cafards", "moustiques", "punaises", '
    '"rongeurs", "fourmis", ou null) et le NIVEAU d\'infestation visible '
    '(estimation.niveau : "faible", "moyenne" ou "forte"). quantite_min / '
    "quantite_max : null.",
}


def normaliser(brut):
    """Garde uniquement les champs attendus, aux bons types."""
    brut = brut if isinstance(brut, dict) else {}
    e = brut.get("estimation") if isinstance(brut.get("estimation"), dict) else {}

    def entier(v):
        if isinstance(v, bool) or not isinstance(v, (int, float)) or v < 0:
            return None
        return int(round(v))

    def texte(v, permis):
        return v if isinstance(v, str) and v in permis else None

    confiance = brut.get("confiance")
    confiance = (
        min(1.0, max(0.0, float(confiance)))
        if isinstance(confiance, (int, float)) and not isinstance(confiance, bool)
        else 0.0
    )
    incoherences = brut.get("incoherences")
    raison = brut.get("raison_non_conforme")
    return {
        "photos_conformes": brut.get("photos_conformes") is not False,
        "raison_non_conforme": raison[:300] if isinstance(raison, str) else None,
        "estimation": {
            "quantite_min": entier(e.get("quantite_min")),
            "quantite_max": entier(e.get("quantite_max")),
            "niveau": texte(
                e.get("niveau"), ["normal", "sale", "tres_sale", "faible", "moyenne", "forte"]
            ),
            "nuisible": texte(
                e.get("nuisible"), ["cafards", "moustiques", "punaises", "rongeurs", "fourmis"]
            ),
        },
        "confiance": confiance,
        "incoherences": [x[:200] for x in incoherences if isinstance(x, str)][:5]
        if isinstance(incoherences, list)
        else [],
    }


def _consigne(service, reponses):
    return (
        "Tu vérifies les photos d'une demande de service à domicile au Cameroun, "
        "pour fixer un prix juste.\n{}\n\nRéponses du client au questionnaire : {}.\n\n"
        "1. Vérifie que les photos montrent bien ce qui est demandé (sinon "
        "photos_conformes = false et explique dans raison_non_conforme).\n"
        "2. Estime ce qui est demandé ci-dessus.\n"
        "3. Compare avec les réponses du client et liste chaque incohérence en une "
        "phrase courte en français (ex. « Environ 4 sacs visibles, 2 déclarés »).\n"
        "4. confiance : de 0 à 1.\n\nRéponds UNIQUEMENT en JSON, exactement ce format :\n"
        '{{"photos_conformes": true, "raison_non_conforme": null, '
        '"estimation": {{"quantite_min": null, "quantite_max": null, '
        '"niveau": null, "nuisible": null}}, "confiance": 0.0, "incoherences": []}}'
    ).format(CONSIGNES[service], json.dumps(reponses or {}, ensure_ascii=False))


def appeler_groq(cle, modele, consigne, images):
    corps = {
        "model": modele,
        "temperature": 0.2,
        "response_format": {"type": "json_object"},
        "messages": [
            {
                "role": "user",
                "content": [{"type": "text", "text": consigne}]
                + [
                    {
                        "type": "image_url",
                        "image_url": {"url": "data:image/jpeg;base64," + b64},
                    }
                    for b64 in images
                ],
            }
        ],
    }
    requete = urllib.request.Request(
        "https://api.groq.com/openai/v1/chat/completions",
        data=json.dumps(corps).encode(),
        headers={"Authorization": "Bearer " + cle, "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(requete, timeout=DELAI) as reponse:
        decode = json.loads(reponse.read())
    return decode["choices"][0]["message"]["content"]


def analyser(citoyen, service, reponses, photos):
    """Analyse et enregistre. Renvoie toujours une AnalyseIA (resultat None
    en cas d'échec, avec la cause dans `erreur`)."""
    modele = os.environ.get("GROQ_VISION_MODEL") or MODELE_PAR_DEFAUT

    def terminer(resultat, erreur=""):
        return AnalyseIA.objects.create(
            citoyen=citoyen, service=service, reponses=reponses or {},
            photos=photos, resultat=resultat, erreur=erreur, modele=modele,
        )

    cle = os.environ.get("GROQ_API_KEY")
    if not cle:
        return terminer(None, "configuration")
    images = []
    for chemin in photos:
        if not stockage.existe(chemin):
            return terminer(None, "photo_introuvable")
        with stockage.ouvrir(chemin) as f:
            donnees = f.read(MAX_OCTETS + 1)
        if len(donnees) > MAX_OCTETS:
            return terminer(None, "photo_trop_lourde")
        images.append(base64.b64encode(donnees).decode())
    try:
        contenu = appeler_groq(cle, modele, _consigne(service, reponses), images)
    except urllib.error.HTTPError as exc:
        return terminer(None, "groq_{}".format(exc.code))
    except (urllib.error.URLError, OSError, KeyError, IndexError, ValueError):
        return terminer(None, "erreur_ia")
    try:
        return terminer(normaliser(json.loads(contenu)))
    except (TypeError, ValueError):
        return terminer(None, "reponse_illisible")
