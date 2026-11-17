"""Calcul du prix d'une demande : copie exacte de la fonction SQL
calculer_prix (supabase/sql/009_tarification.sql) et du calcul Dart
(lib/data/pricing/tarification.dart).

Prix = temps estimé × tarif horaire + déplacement + produits, arrondi à la
centaine supérieure ; abonnement = prix d'un passage × passages du mois,
moins la remise.

Tout est en entiers, avec les mêmes arrondis que PostgreSQL : les trois
implémentations doivent donner le même montant au franc près (voir les 8 cas
de contrôle dans tests.py, communs au SQL et au Dart).
"""
import re
from decimal import ROUND_HALF_UP, Decimal

SERVICES = ("menage", "linge", "dechets", "nuisibles")
FORMULES = ("ponctuelle", "abonnement")
FREQUENCES = ("hebdomadaire", "mensuel")


class ServiceInconnu(ValueError):
    pass


def arrondi(valeur):
    """round() de PostgreSQL sur un numeric : demi à l'écart de zéro."""
    return int(Decimal(str(valeur)).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def _div(a, b):
    """Division entière de PostgreSQL : tronquée vers zéro."""
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b > 0) else -q


def _tarif(tarifs, service, cle):
    valeur = (tarifs.get(service) or {}).get(cle)
    return arrondi(valeur) if valeur is not None else 0


def _entier(reponses, cle):
    """Entier d'une réponse : 0 si absente ou non numérique, tronqué."""
    v = reponses.get(cle)
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return 0
    return int(v)


def _oui(reponses, cle):
    return reponses.get(cle) is True


def _texte(reponses, cle):
    """Équivalent de « r ->> cle » : texte de la valeur, None si absente."""
    v = reponses.get(cle)
    if v is None:
        return None
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v)


def _centaine(x):
    return 0 if x <= 0 else _div(x + 99, 100) * 100


def calculer_prix(tarifs, service, formule, frequence, reponses, produits):
    """Prix d'une demande. `tarifs` : {service: {cle: valeur}}."""
    r = reponses or {}
    s = service
    minutes = 0
    montant_produits = 0
    ps = 1  # passages par semaine (déchets)
    hebdo = formule == "abonnement" and frequence == "hebdomadaire"

    if s == "menage":
        for cle_rep, cle_tarif in (
            ("chambres", "chambre"),
            ("salons", "salon"),
            ("cuisines", "cuisine"),
            ("douche_wc", "douche_wc"),
            ("canapes", "canape"),
            ("tapis", "tapis"),
        ):
            minutes += max(_entier(r, cle_rep), 0) * _tarif(tarifs, s, cle_tarif)
        for option in ("vitres", "frigo", "four"):
            if _oui(r, option):
                minutes += _tarif(tarifs, s, option)
        maj = {
            "sale": _tarif(tarifs, s, "etat_sale"),
            "tres_sale": _tarif(tarifs, s, "etat_tres_sale"),
        }.get(_texte(r, "etat"), 0)
        if maj > 0:
            minutes = _div(minutes * (100 + maj) + 99, 100)
        if produits:
            montant_produits = _tarif(tarifs, s, "produits")

    elif s == "linge":
        n = max(_entier(r, "paniers"), 1)
        minutes = n * _tarif(tarifs, s, "panier")
        if _oui(r, "draps_delicats"):
            minutes += n * _tarif(tarifs, s, "draps_delicats")
        if _oui(r, "repassage"):
            minutes += max(_entier(r, "pieces_repassage"), 0) * _tarif(tarifs, s, "piece_repassage")
        if produits:
            montant_produits = n * _tarif(tarifs, s, "produits")

    elif s == "dechets":
        if hebdo:
            ps = min(max(_entier(r, "passages_semaine"), 1), 7)
            n = _div(_entier(r, "sacs") + ps - 1, ps)
        else:
            n = _entier(r, "sacs")
        minutes = max(n, 0) * _tarif(tarifs, s, "sac") + max(_entier(r, "etage"), 0) * _tarif(
            tarifs, s, "etage"
        )
        distance = _texte(r, "distance_bac")
        if distance is not None and re.fullmatch(r"[0-9]+", distance):
            minutes += _div(int(distance) + 9, 10) * _tarif(tarifs, s, "distance_10m")
        minutes = max(minutes, _tarif(tarifs, s, "minimum"))

    elif s == "nuisibles":
        n = max(_entier(r, "pieces"), 1)
        minutes = n * _tarif(tarifs, s, "piece")
        base = n * _tarif(tarifs, s, "produit_" + (_texte(r, "nuisible") or "cafards"))
        maj = {
            "moyenne": _tarif(tarifs, s, "infestation_moyenne"),
            "forte": _tarif(tarifs, s, "infestation_forte"),
        }.get(_texte(r, "infestation"), 0)
        montant_produits = _div(base * (100 + maj) + 99, 100)

    else:
        raise ServiceInconnu(service)

    main_oeuvre = _div(minutes * _tarif(tarifs, "global", "tarif_horaire") + 30, 60)
    deplacement = _tarif(tarifs, "global", "deplacement")
    prix_passage = _centaine(main_oeuvre + deplacement + montant_produits)
    passages = 4 * ps if hebdo else 1
    remise = _tarif(tarifs, "global", "remise_abonnement") if formule == "abonnement" else 0
    prix_total = _centaine(_div(prix_passage * passages * (100 - remise) + 99, 100))

    return {
        "minutes": minutes,
        "main_oeuvre": main_oeuvre,
        "deplacement": deplacement,
        "produits": montant_produits,
        "prix_passage": prix_passage,
        "passages": passages,
        "prix_total": prix_total,
    }


def prix_ajustement(tarifs, minutes, produits):
    """Supplément d'un ajustement : temps au tarif horaire + produits,
    arrondi à la centaine supérieure (comme demander_ajustement en SQL)."""
    return _centaine(
        _div((minutes or 0) * _tarif(tarifs, "global", "tarif_horaire") + 30, 60) + (produits or 0)
    )
