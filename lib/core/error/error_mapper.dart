import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import 'app_exception.dart';
import 'app_logger.dart';

/// Traduit n'importe quelle erreur (API, réseau, inattendue) en
/// [AppException] avec un message français adapté à l'utilisateur final,
/// tout en loggant systématiquement l'erreur technique d'origine.
/// Refus métier de l'API (mêmes codes que les anciennes fonctions SQL) :
/// code → message pour l'utilisateur.
const _messagesSql = {
  'PRESTATAIRE_INDISPONIBLE':
      "Ce prestataire n'est plus disponible pour ce service. Choisissez-en un autre.",
  'PHOTOS_REQUISES': 'Ajoutez au moins une photo (trois au maximum).',
  'PHOTO_INVALIDE': "Photo non valide : reprenez-la depuis l'application.",
  'DATE_INVALIDE': "Choisissez une date à partir d'aujourd'hui.",
  'PROFIL_CITOYEN_INCOMPLET':
      'Complétez votre profil (nom et téléphone) avant de réserver.',
  'CITOYEN_INCONNU': 'Complétez votre profil avant de réserver.',
  'DEMANDE_VIA_SERVEUR': "Le prix d'une demande ne peut pas être modifié.",
  'PRIX_PROTEGE': "Le prix d'une demande ne peut pas être modifié.",
  'TRANSITION_INTERDITE':
      "Cette action n'est plus possible pour cette demande.",
  'AJUSTEMENT_DEJA_EN_ATTENTE':
      'Un ajustement attend déjà la réponse du client.',
  'AJUSTEMENT_IMPOSSIBLE':
      "Un ajustement n'est possible que sur une mission confirmée.",
  'AJUSTEMENT_VIDE': 'Indiquez le temps ou les produits en plus.',
  'DEJA_REPONDU': 'Vous avez déjà répondu à cet ajustement.',
  'PASSAGE_DEJA_POINTE': "Le passage d'aujourd'hui est déjà pointé.",
  'PASSAGE_IMPOSSIBLE':
      'Le pointage est possible seulement sur un abonnement confirmé.',
  'NON_AUTORISE': 'Action non autorisée.',
  'IDENTITE_FIGEE':
      "Vos informations sont figées car votre identité est vérifiée ou en cours d'examen.",
  'PROFIL_INCOMPLET':
      'Complétez votre profil (nom, prénom, photo et services) avant de continuer.',
  'AVIS_DEJA_DONNE': 'Vous avez déjà donné votre avis sur cette mission.',
  'avis_sollicitation_unique':
      'Vous avez déjà donné votre avis sur cette mission.',
  'DOCUMENT_DEJA_UTILISE':
      "Cette pièce d'identité est déjà associée à un compte WANDA.",
  'CONSENTEMENT_REQUIS':
      "Vous devez accepter les conditions de traitement des pièces d'identité.",
  'CERTIFICATION_EN_COURS':
      "Une demande de vérification est déjà en cours d'examen.",
};

AppException mapError(String context, Object error, [StackTrace? stackTrace]) {
  AppLogger.error(context, error, stackTrace);

  // Refus de l'API WANDA : message du serveur, ou celui de l'app pour les
  // codes qu'elle formule mieux.
  if (error is ApiException) {
    final message = _messagesSql[error.code];
    return message == null
        ? error
        : ApiException(message,
            code: error.code, statut: error.statut, cause: error);
  }

  if (error is AppException) return error;

  if (error is SocketException ||
      error is TimeoutException ||
      error is http.ClientException) {
    return AppException(
        'Problème de connexion internet. Vérifiez votre réseau.',
        cause: error,
        stackTrace: stackTrace);
  }

  return AppException('Une erreur inattendue est survenue.',
      cause: error, stackTrace: stackTrace);
}
