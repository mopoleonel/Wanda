from django.db import IntegrityError, transaction
from django.utils import timezone

from noyau import stockage
from noyau.erreurs import ErreurMetier
from notifications.services import notifier

from .models import JournalVerification, Verification


def deposer(prestataire, fichiers, donnees):
    """Nouvelle demande de certification (toujours « en attente »)."""
    if not prestataire.profil_complet:
        raise ErreurMetier("PROFIL_INCOMPLET")
    if prestataire.verifications.filter(statut="en_attente").exists():
        raise ErreurMetier("CERTIFICATION_EN_COURS", status_code=409)
    if not donnees.get("consentement"):
        raise ErreurMetier("CONSENTEMENT_REQUIS")
    numero = (donnees.get("numero_document") or "").strip().upper()
    if numero and Verification.objects.filter(numero_document=numero).exclude(
        statut="rejete"
    ).exclude(prestataire=prestataire).exists():
        raise ErreurMetier("DOCUMENT_DEJA_UTILISE", status_code=409)

    if any(fichiers.get(piece) is None for piece in ("recto", "verso", "selfie")):
        raise ErreurMetier("FICHIER_INVALIDE")
    dossier = timezone.now().strftime("%Y%m%d%H%M%S")
    chemins = {
        piece: stockage.enregistrer(fichiers.get(piece), "identites", prestataire.pk, dossier)
        for piece in ("recto", "verso", "selfie")
    }
    try:
        with transaction.atomic():
            v = Verification.objects.create(
                prestataire=prestataire,
                numero_document=numero,
                nom=donnees["nom"].strip(),
                prenoms=donnees["prenoms"].strip(),
                date_naissance=donnees.get("date_naissance"),
                lieu_naissance=(donnees.get("lieu_naissance") or "").strip(),
                sexe=donnees.get("sexe") or "",
                date_expiration=donnees.get("date_expiration"),
                mrz_presente=bool(donnees.get("mrz_presente")),
                mrz_valide=bool(donnees.get("mrz_valide")),
                saisie_corrigee=bool(donnees.get("saisie_corrigee")),
                consentement_le=timezone.now(),
                consentement_version=donnees["consentement_version"],
                consentement_texte=donnees["consentement_texte"],
                **chemins,
            )
            JournalVerification.objects.create(
                verification=v, action="creation", nouveau_statut=v.statut,
                acteur=prestataire.utilisateur,
                details="consentement " + v.consentement_version,
            )
    except IntegrityError:
        raise ErreurMetier("DOCUMENT_DEJA_UTILISE", status_code=409)
    return v


def decider(verification, admin, valide, motif=""):
    """Décision de l'équipe WANDA : met à jour le badge et le journal, et
    prévient le prestataire."""
    with transaction.atomic():
        v = Verification.objects.select_for_update().select_related("prestataire").get(
            pk=verification.pk
        )
        if v.statut != "en_attente":
            return v
        ancien = v.statut
        v.statut = "valide" if valide else "rejete"
        v.motif_rejet = "" if valide else (motif or "Pièce non conforme")[:300]
        v.verifie_par = admin
        v.verifie_le = timezone.now()
        v.save(update_fields=["statut", "motif_rejet", "verifie_par", "verifie_le"])
        JournalVerification.objects.create(
            verification=v, action=v.statut, ancien_statut=ancien,
            nouveau_statut=v.statut, acteur=admin, details=v.motif_rejet,
        )
        p = v.prestataire
        p.identite_verifiee = valide
        p.save(update_fields=["identite_verifiee"])
        if valide:
            notifier(p.utilisateur, "Identité vérifiée",
                     "Votre badge « Identité vérifiée » est visible des clients.")
        else:
            notifier(p.utilisateur, "Certification refusée",
                     "{}. Vous pouvez envoyer une nouvelle demande.".format(v.motif_rejet))
    return v
