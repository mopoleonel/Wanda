"""Erreurs métier : un code stable (le même que dans les fonctions SQL de
Supabase, que l'app sait déjà traduire) et un message en français.

Réponse de l'API : {"code": "PRIX_PROTEGE", "message": "..."}.
"""
from rest_framework import status
from rest_framework.exceptions import APIException
from rest_framework.views import exception_handler

# Messages affichables tels quels dans l'app.
MESSAGES = {
    "NON_CONNECTE": "Connectez-vous pour continuer.",
    "NON_AUTORISE": "Action non autorisée.",
    "CITOYEN_INCONNU": "Complétez votre profil avant de réserver.",
    "PROFIL_CITOYEN_INCOMPLET": "Indiquez votre nom avant de réserver.",
    "PRESTATAIRE_INDISPONIBLE": "Ce prestataire n'est plus disponible. Choisissez-en un autre.",
    "PHOTOS_REQUISES": "Ajoutez entre une et trois photos.",
    "PHOTO_INVALIDE": "Une photo jointe n'est pas valide.",
    "DATE_INVALIDE": "Choisissez une date à venir.",
    "SERVICE_INCONNU": "Service inconnu.",
    "FORMULE_INVALIDE": "Formule ou rythme invalide.",
    "TRANSITION_INTERDITE": "Cette action n'est pas possible à ce stade de la demande.",
    "AJUSTEMENT_IMPOSSIBLE": "Un ajustement n'est possible que sur une demande confirmée.",
    "AJUSTEMENT_VIDE": "Indiquez du temps ou des produits en plus.",
    "AJUSTEMENT_DEJA_EN_ATTENTE": "Un ajustement attend déjà la réponse du client.",
    "MOTIF_REQUIS": "Expliquez la raison de l'ajustement.",
    "DEJA_REPONDU": "Cet ajustement a déjà reçu une réponse.",
    "PASSAGE_IMPOSSIBLE": "Le pointage concerne un abonnement confirmé.",
    "PASSAGE_DEJA_POINTE": "Le passage d'aujourd'hui est déjà pointé.",
    "AVIS_IMPOSSIBLE": "On ne note qu'une mission terminée.",
    "AVIS_DEJA_DONNE": "Vous avez déjà noté cette mission.",
    "IDENTITE_FIGEE": "Ces informations sont figées depuis la certification.",
    "PROFIL_INCOMPLET": "Complétez votre profil (photo, nom, prénom, services) avant de certifier.",
    "CERTIFICATION_EN_COURS": "Une certification est déjà en cours d'examen.",
    "DOCUMENT_DEJA_UTILISE": "Cette pièce d'identité est déjà utilisée par un autre compte.",
    "CONSENTEMENT_REQUIS": "Acceptez les conditions pour envoyer votre certification.",
    "ESSAI_DEJA_UTILISE": "L'essai gratuit a déjà été utilisé.",
    "ABONNEMENT_REQUIS": "Un abonnement actif est nécessaire pour passer en ligne.",
    "TELEPHONE_INVALIDE": "Numéro de téléphone invalide.",
    "CODE_INVALIDE": "Code incorrect.",
    "CODE_EXPIRE": "Code expiré : demandez-en un nouveau.",
    "TROP_D_ESSAIS": "Trop d'essais : demandez un nouveau code.",
    "ENVOI_CODE_IMPOSSIBLE": "Impossible d'envoyer le code pour le moment.",
    "TYPE_COMPTE_FIGE": "Ce numéro est déjà utilisé pour un autre type de compte.",
    "FICHIER_INVALIDE": "Fichier invalide : une photo JPEG ou PNG de 5 Mo au plus.",
    "LIEN_EXPIRE": "Ce lien a expiré.",
}


class ErreurMetier(APIException):
    """Refus d'une règle métier. Toujours levée avec un code de MESSAGES."""

    status_code = status.HTTP_400_BAD_REQUEST

    def __init__(self, code, status_code=None, message=None):
        self.code_metier = code
        if status_code is not None:
            self.status_code = status_code
        super().__init__(message or MESSAGES.get(code, code), code)


class NonAutorise(ErreurMetier):
    status_code = status.HTTP_403_FORBIDDEN

    def __init__(self, code="NON_AUTORISE"):
        super().__init__(code)


def gestionnaire_erreurs(exc, context):
    """Format unique des erreurs : {"code", "message"} (+ "champs" si
    la saisie est invalide)."""
    reponse = exception_handler(exc, context)
    if reponse is None:
        return None
    if isinstance(exc, ErreurMetier):
        reponse.data = {"code": exc.code_metier, "message": str(exc.detail)}
    elif reponse.status_code == 400:
        reponse.data = {
            "code": "SAISIE_INVALIDE",
            "message": "Certaines informations sont invalides.",
            "champs": reponse.data,
        }
    elif reponse.status_code == 401:
        reponse.data = {"code": "NON_CONNECTE", "message": MESSAGES["NON_CONNECTE"]}
    elif reponse.status_code == 403:
        reponse.data = {"code": "NON_AUTORISE", "message": MESSAGES["NON_AUTORISE"]}
    elif reponse.status_code == 404:
        reponse.data = {"code": "INTROUVABLE", "message": "Élément introuvable."}
    elif reponse.status_code == 429:
        reponse.data = {
            "code": "TROP_DE_DEMANDES",
            "message": "Trop de demandes : réessayez dans quelques minutes.",
        }
    return reponse
