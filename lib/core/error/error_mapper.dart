import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_exception.dart';
import 'app_logger.dart';

/// Traduit n'importe quelle erreur (Supabase, réseau, inattendue) en
/// [AppException] avec un message français adapté à l'utilisateur final,
/// tout en loggant systématiquement l'erreur technique d'origine.
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
    if (error.message.contains('IDENTITE_NON_VERIFIEE')) {
      return AppException(
          'Votre identité doit être validée avant de passer en ligne.',
          cause: error,
          stackTrace: stackTrace);
    }
    if (error.message.contains('IDENTITE_FIGEE')) {
      return AppException(
          "Compte certifié : nom, prénom, métier et numéro ne peuvent plus être modifiés. Contactez l'équipe WANDA pour une correction.",
          cause: error,
          stackTrace: stackTrace);
    }
    if (error.message.contains('PROFIL_INCOMPLET')) {
      return AppException(
          'Complétez votre profil (photo, nom, prénom, métier) avant de demander la certification.',
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
