"""Règles métier des demandes : le seul endroit qui écrit une demande.

Mêmes règles que les fonctions SQL de Supabase (011, 012, 013), avec les
mêmes codes d'erreur :
  * creer_demande      : prix recalculé ici, jamais fourni par l'app ;
  * changer_statut     : seules les transitions prévues, par la bonne partie ;
  * ajustements        : le prestataire demande, le client accepte ou refuse ;
  * pointer_passage    : abonnement, un passage par jour ;
  * noter              : une note par mission terminée.
Chaque étape prévient l'autre partie (notifications).
"""
from django.db import IntegrityError, transaction
from django.utils import timezone

from comptes.models import Prestataire
from noyau import stockage
from noyau.erreurs import ErreurMetier, NonAutorise
from notifications.services import libelle_service, montant, notifier
from tarification import calcul
from tarification.models import prix_demande, tarifs_actuels

from .models import AnalyseIA, Ajustement, Avis, Demande, Passage, numero_fiche

# (ancien statut, nouveau statut) permis, selon qui agit.
TRANSITIONS_PRESTATAIRE = {
    ("en_attente", "accepte"),
    ("en_attente", "refuse"),
    ("accepte", "termine"),
}
TRANSITIONS_CITOYEN = {
    ("en_attente", "annule"),
    ("accepte", "annule"),
    ("termine", "archive"),
    ("annule", "archive"),
    ("refuse", "archive"),
}


def _photos_valides(photos, auteur_id, minimum, maximum):
    if not isinstance(photos, list) or not minimum <= len(photos) <= maximum:
        raise ErreurMetier("PHOTOS_REQUISES")
    for chemin in photos:
        if (
            not isinstance(chemin, str)
            or not chemin.startswith("demandes/")
            or not stockage.appartient_a(chemin, auteur_id)
            or not stockage.existe(chemin)
        ):
            raise ErreurMetier("PHOTO_INVALIDE")


def creer_demande(utilisateur, *, prestataire_id, service, formule, frequence, reponses,
                  produits, photos, analyse_id, date, creneau):
    citoyen = getattr(utilisateur, "citoyen", None)
    if citoyen is None:
        raise ErreurMetier("CITOYEN_INCONNU")
    if not citoyen.nom.strip() or not citoyen.telephone.strip():
        raise ErreurMetier("PROFIL_CITOYEN_INCOMPLET")
    if service not in calcul.SERVICES:
        raise ErreurMetier("SERVICE_INCONNU")
    if formule not in calcul.FORMULES or (
        formule == "abonnement" and frequence not in calcul.FREQUENCES
    ):
        raise ErreurMetier("FORMULE_INVALIDE")

    prestataire = Prestataire.objects.filter(pk=prestataire_id).first()
    if (
        prestataire is None
        or not prestataire.en_ligne
        or not prestataire.abonnement_valide
        or service not in prestataire.services
    ):
        raise ErreurMetier("PRESTATAIRE_INDISPONIBLE")

    _photos_valides(photos, utilisateur.pk, 1, 3)
    if date is None or date < timezone.localdate():
        raise ErreurMetier("DATE_INVALIDE")

    frequence = frequence if formule == "abonnement" else ""
    prix = prix_demande(service, formule, frequence or None, reponses or {}, produits)

    ia = None
    if analyse_id:
        analyse = AnalyseIA.objects.filter(pk=analyse_id, citoyen=citoyen).first()
        ia = analyse.resultat if analyse else None

    with transaction.atomic():
        demande = Demande.objects.create(
            prestataire=prestataire,
            citoyen=citoyen,
            nom_citoyen=citoyen.nom,
            prenom_citoyen=citoyen.prenom,
            numero_citoyen=citoyen.telephone,
            service=service,
            formule=formule,
            frequence=frequence,
            reponses=reponses or {},
            produits_fournis=bool(produits) or service == "nuisibles",
            minutes_estimees=prix["minutes"],
            prix_passage=prix["prix_passage"],
            prix_total=prix["prix_total"],
            prix_detail=prix,
            photos=photos,
            ia_analyse=ia,
            date_souhaitee=date,
            creneau=creneau,
        )
        notifier(
            prestataire.utilisateur,
            "Nouvelle demande : " + libelle_service(service),
            "{} · {}. Consultez la demande pour accepter ou refuser.".format(
                citoyen.nom or "Un client", montant(demande.prix_total)
            ),
            demande=demande.pk,
        )
    return demande


def _role(demande, utilisateur):
    if demande.prestataire_id == utilisateur.pk:
        return "prestataire"
    if demande.citoyen_id == utilisateur.pk:
        return "citoyen"
    return None


def changer_statut(demande_id, utilisateur, nouveau, motif=""):
    with transaction.atomic():
        demande = (
            Demande.objects.select_for_update()
            .select_related("prestataire", "citoyen")
            .filter(pk=demande_id)
            .first()
        )
        if demande is None:
            raise NonAutorise()
        role = _role(demande, utilisateur)
        permises = {
            "prestataire": TRANSITIONS_PRESTATAIRE,
            "citoyen": TRANSITIONS_CITOYEN,
        }.get(role)
        if permises is None:
            raise NonAutorise()
        if (demande.statut, nouveau) not in permises:
            raise ErreurMetier("TRANSITION_INTERDITE", status_code=409)

        demande.statut = nouveau
        champs = ["statut", "modifie_le"]
        p = demande.prestataire
        if nouveau == "refuse":
            demande.motif_refus = (motif or "").strip()[:200]
            champs.append("motif_refus")
        if nouveau == "termine":
            demande.date_fin = timezone.now()
            champs.append("date_fin")
        demande.save(update_fields=champs)

        # Disponibilité du prestataire : hors ligne pendant une mission, de
        # nouveau en ligne à la fin si son abonnement le permet.
        if nouveau == "accepte" and p.en_ligne:
            p.en_ligne = False
            p.save(update_fields=["en_ligne"])
        elif nouveau == "termine" and p.abonnement_valide and not p.en_ligne:
            p.en_ligne = True
            p.save(update_fields=["en_ligne"])

        client = demande.citoyen.utilisateur
        fiche = numero_fiche(demande.pk)
        if nouveau == "accepte":
            notifier(client, "Demande confirmée",
                     "Votre prestataire a accepté : {}.".format(libelle_service(demande.service)),
                     demande=demande.pk)
        elif nouveau == "refuse":
            notifier(client, "Demande refusée",
                     "Le prestataire n'est pas disponible. Choisissez-en un autre "
                     "depuis votre demande.", demande=demande.pk)
        elif nouveau == "termine":
            notifier(client, "Service terminé", "Pensez à noter votre prestataire.",
                     demande=demande.pk)
        elif nouveau == "annule":
            notifier(p.utilisateur, "Demande annulée",
                     "Le client a annulé la demande N° {}.".format(fiche), demande=demande.pk)
    return demande


def demander_ajustement(demande_id, utilisateur, *, minutes, produits, motif, photos):
    with transaction.atomic():
        demande = Demande.objects.select_for_update().filter(pk=demande_id).first()
        if demande is None or demande.prestataire_id != utilisateur.pk:
            raise NonAutorise()
        if demande.statut != "accepte":
            raise ErreurMetier("AJUSTEMENT_IMPOSSIBLE", status_code=409)
        minutes, produits = minutes or 0, produits or 0
        if not (0 <= minutes <= 600 and 0 <= produits <= 100000):
            raise ErreurMetier("AJUSTEMENT_VIDE")
        if minutes <= 0 and produits <= 0:
            raise ErreurMetier("AJUSTEMENT_VIDE")
        motif = (motif or "").strip()
        if not 3 <= len(motif) <= 500:
            raise ErreurMetier("MOTIF_REQUIS")
        if photos:
            _photos_valides(photos, utilisateur.pk, 1, 3)
        if demande.ajustements.filter(statut="en_attente").exists():
            raise ErreurMetier("AJUSTEMENT_DEJA_EN_ATTENTE", status_code=409)

        prix = calcul.prix_ajustement(tarifs_actuels(), minutes, produits)
        try:
            with transaction.atomic():
                ajustement = Ajustement.objects.create(
                    demande=demande, minutes_supp=minutes, produits_supp=produits,
                    motif=motif, photos=photos or [], prix_supp=prix,
                )
        except IntegrityError:
            raise ErreurMetier("AJUSTEMENT_DEJA_EN_ATTENTE", status_code=409)
        demande.save(update_fields=["modifie_le"])
        notifier(demande.citoyen.utilisateur, "Ajustement demandé",
                 "Votre prestataire demande +{}. Acceptez ou refusez dans "
                 "« Mes demandes ».".format(montant(prix)), demande=demande.pk)
    return ajustement


def repondre_ajustement(ajustement_id, utilisateur, accepte):
    with transaction.atomic():
        ajustement = (
            Ajustement.objects.select_for_update()
            .select_related("demande")
            .filter(pk=ajustement_id)
            .first()
        )
        if ajustement is None or ajustement.demande.citoyen_id != utilisateur.pk:
            raise NonAutorise()
        if ajustement.statut != "en_attente":
            raise ErreurMetier("DEJA_REPONDU", status_code=409)
        ajustement.statut = "accepte" if accepte else "refuse"
        ajustement.repondu_le = timezone.now()
        ajustement.save(update_fields=["statut", "repondu_le"])

        demande = Demande.objects.select_for_update().get(pk=ajustement.demande_id)
        if accepte:
            demande.prix_total += ajustement.prix_supp
            demande.minutes_estimees += ajustement.minutes_supp
            demande.save(update_fields=["prix_total", "minutes_estimees", "modifie_le"])
        else:
            demande.save(update_fields=["modifie_le"])
        notifier(
            demande.prestataire.utilisateur,
            "Ajustement accepté" if accepte else "Ajustement refusé",
            "Le client a accepté +{}.".format(montant(ajustement.prix_supp))
            if accepte else "Le client a refusé : le prix initial reste dû.",
            demande=demande.pk,
        )
    return ajustement


def pointer_passage(demande_id, utilisateur):
    with transaction.atomic():
        demande = Demande.objects.select_for_update().filter(pk=demande_id).first()
        if demande is None or demande.prestataire_id != utilisateur.pk:
            raise NonAutorise()
        if demande.formule != "abonnement" or demande.statut != "accepte":
            raise ErreurMetier("PASSAGE_IMPOSSIBLE", status_code=409)
        jour = timezone.localdate()
        if demande.passages.filter(jour=jour).exists():
            raise ErreurMetier("PASSAGE_DEJA_POINTE", status_code=409)
        passage = Passage.objects.create(demande=demande, jour=jour)
        demande.save(update_fields=["modifie_le"])
        notifier(demande.citoyen.utilisateur, "Passage effectué",
                 "Votre prestataire a pointé le passage d'aujourd'hui.", demande=demande.pk)
    return passage


def noter(demande_id, utilisateur, note, commentaire=""):
    with transaction.atomic():
        demande = Demande.objects.select_for_update().filter(pk=demande_id).first()
        if demande is None or demande.citoyen_id != utilisateur.pk:
            raise NonAutorise()
        if demande.statut not in ("termine", "archive"):
            raise ErreurMetier("AVIS_IMPOSSIBLE", status_code=409)
        if Avis.objects.filter(demande=demande).exists():
            raise ErreurMetier("AVIS_DEJA_DONNE", status_code=409)
        return Avis.objects.create(
            demande=demande,
            prestataire_id=demande.prestataire_id,
            citoyen_id=demande.citoyen_id,
            note=note,
            commentaire=(commentaire or "").strip()[:500],
        )


def peut_voir_photo(utilisateur, chemin):
    """Qui obtient un lien vers une photo privée :
      * son auteur ;
      * le prestataire d'une demande qui la contient ;
      * le client d'une demande dont un ajustement la contient ;
      * toute personne connectée pour une photo de profil (publique)."""
    if not isinstance(chemin, str):
        return False
    if chemin.startswith("profils/"):
        return True
    if stockage.appartient_a(chemin, utilisateur.pk):
        return True
    if not chemin.startswith("demandes/"):
        return False
    pour_le_prestataire = Demande.objects.filter(prestataire_id=utilisateur.pk).values_list(
        "photos", flat=True
    )
    if any(chemin in (photos or []) for photos in pour_le_prestataire):
        return True
    pour_le_client = Ajustement.objects.filter(demande__citoyen_id=utilisateur.pk).values_list(
        "photos", flat=True
    )
    return any(chemin in (photos or []) for photos in pour_le_client)
