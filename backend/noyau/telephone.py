"""Numéros de téléphone au format E.164, comme dans l'app
(lib/core/utils/phone_utils.dart) : « 690 00 00 01 » -> « +237690000001 »."""
import re

INDICATIF_DEFAUT = "237"


def normaliser(saisie, indicatif=INDICATIF_DEFAUT):
    """Renvoie le numéro « +XXXXXXXX » ou None s'il est invalide."""
    valeur = re.sub(r"[\s\-\.\(\)]", "", saisie or "")
    if not valeur:
        return None
    if valeur.startswith("00"):
        valeur = "+" + valeur[2:]
    if valeur.startswith("+"):
        chiffres = valeur[1:]
    elif valeur.startswith(indicatif) and len(valeur) > len(indicatif) + 8:
        chiffres = valeur
    else:
        chiffres = indicatif + valeur
    if not re.fullmatch(r"[1-9]\d{7,14}", chiffres):
        return None
    return "+" + chiffres
