import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_exception.dart';
import 'app_logger.dart';

/// Traduit n'importe quelle erreur (Supabase, réseau, inattendue) en
/// [AppException] avec un message français adapté à l'utilisateur final,
/// tout en loggant systématiquement l'erreur technique d'origine.
/// Refus métier levés par les fonctions SQL (011 et suivantes) : code de
/// l'exception → message pour l'utilisateur.
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

  if (error is AppException) return error;

  if (error is AuthException) {
    final msg = error.message;
    if (msg.contains('already registered') ||
        msg.contains('User already registered')) {
      return AppException(
          'Cet email est déjà utilisé. Essayez de vous connecter.',
          cause: error,
          stackTrace: stackTrace);
    }
    if (msg.contains('Invalid login credentials')) {
      return AppException('Email ou mot de passe incorrect.',
          cause: error, stackTrace: stackTrace);
    }
    if (msg.toLowerCase().contains('email not confirmed')) {
      return AppException('Confirmez votre email avant de vous connecter.',
          cause: error, stackTrace: stackTrace);
    }
    final lower = msg.toLowerCase();
    if (lower.contains('token has expired') ||
        lower.contains('otp has expired') ||
        lower.contains('invalid otp')) {
      return AppException('Code invalide ou expiré.',
          cause: error, stackTrace: stackTrace);
    }
    if (lower.contains('for security purposes') ||
        lower.contains('rate limit') ||
        error.statusCode == '429') {
      return AppException(
          'Trop de tentatives. Patientez un peu avant de redemander un code.',
          cause: error,
          stackTrace: stackTrace);
    }
    // Fournisseur d'envoi (Twilio / WhatsApp) absent, mal configuré ou en
    // panne : ce n'est pas une erreur de l'utilisateur.
    if (error.code == 'sms_send_failed' ||
        lower.contains('error sending') ||
        lower.contains('phone provider') ||
        lower.contains('phone signups are disabled') ||
        lower.contains('whatsapp')) {
      return AppException(
          "L'envoi du code WhatsApp est momentanément indisponible. Réessayez dans quelques minutes.",
          cause: error,
          stackTrace: stackTrace);
    }
    if (lower.contains('invalid phone') || lower.contains('phone number')) {
      return AppException('Numéro de téléphone invalide.',
          cause: error, stackTrace: stackTrace);
    }
    return AppException("Erreur d'authentification. Vérifiez vos informations.",
        cause: error, stackTrace: stackTrace);
  }

  if (error is PostgrestException) {
    for (final entry in _messagesSql.entries) {
      if (error.message.contains(entry.key)) {
        return AppException(entry.value, cause: error, stackTrace: stackTrace);
      }
    }
    if (error.message.contains('IDENTITE_NON_VERIFIEE')) {
      return AppException(
          'Votre identité doit être validée avant de passer en ligne.',
          cause: error,
          stackTrace: stackTrace);
    }
    if (error.message.contains('IDENTITE_FIGEE')) {
      return AppException(
          "Compte certifié : nom, prénom et numéro ne peuvent plus être modifiés, et vos services ne peuvent plus être retirés. Contactez l'équipe WANDA pour une correction.",
          cause: error,
          stackTrace: stackTrace);
    }
    if (error.message.contains('PROFIL_INCOMPLET')) {
      return AppException(
          'Complétez votre profil (photo, nom, prénom, services) avant de demander la certification.',
          cause: error,
          stackTrace: stackTrace);
    }
    if (error.code == '23505' &&
        error.message.contains('prestataire_verifications_numero_unique')) {
      return AppException(
          'Cette carte d\'identité est déjà associée à un compte WANDA.',
          cause: error,
          stackTrace: stackTrace);
    }
    return AppException('Erreur de base de données. Merci de réessayer.',
        cause: error, stackTrace: stackTrace);
  }

  if (error is StorageException) {
    return AppException("Erreur lors de l'envoi du fichier.",
        cause: error, stackTrace: stackTrace);
  }

  if (error is SocketException || error is TimeoutException) {
    return AppException(
        'Problème de connexion internet. Vérifiez votre réseau.',
        cause: error,
        stackTrace: stackTrace);
  }

  return AppException('Une erreur inattendue est survenue.',
      cause: error, stackTrace: stackTrace);
}
