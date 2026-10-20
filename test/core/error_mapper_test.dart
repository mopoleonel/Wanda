import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wanda/core/error/app_exception.dart';
import 'package:wanda/core/error/error_mapper.dart';

void main() {
  group('mapError', () {
    test('traduit "already registered" en message clair', () {
      final e =
          mapError('test', const AuthException('User already registered'));
      expect(e.message, contains('déjà utilisé'));
    });

    test('traduit "Invalid login credentials"', () {
      final e =
          mapError('test', const AuthException('Invalid login credentials'));
      expect(e.message, contains('incorrect'));
    });

    test('code OTP expiré ou invalide', () {
      final e = mapError(
          'test', const AuthException('Token has expired or is invalid'));
      expect(e.message, 'Code invalide ou expiré.');
    });

    test('trop de demandes de code', () {
      final e = mapError(
          'test',
          const AuthException(
              'For security purposes, you can only request this after 42 seconds.'));
      expect(e.message, contains('Trop de tentatives'));
    });

    test('fournisseur WhatsApp non configuré', () {
      final e =
          mapError('test', const AuthException('Unsupported phone provider'));
      expect(e.message, contains('WhatsApp'));
    });

    test("échec d'envoi du code (Twilio) : pas la faute de l'utilisateur", () {
      final e = mapError(
          'test',
          const AuthException(
              'Error sending confirmation OTP to provider: auth account '
              'AC00 does not exist',
              statusCode: '422',
              code: 'sms_send_failed'));
      expect(e.message, contains('momentanément indisponible'));
    });

    test('refus métier SQL traduits (prix protégé, ajustement…)', () {
      expect(
          mapError('t', const PostgrestException(message: 'PRIX_PROTEGE'))
              .message,
          "Le prix d'une demande ne peut pas être modifié.");
      expect(
          mapError(
                  't',
                  const PostgrestException(
                      message: 'AJUSTEMENT_DEJA_EN_ATTENTE'))
              .message,
          contains('attend déjà'));
      expect(
          mapError('t',
                  const PostgrestException(message: 'PRESTATAIRE_INDISPONIBLE'))
              .message,
          contains("n'est plus disponible"));
    });

    test('PostgrestException -> message générique base de données', () {
      final e = mapError(
          'test', const PostgrestException(message: 'relation does not exist'));
      expect(e.message, contains('base de données'));
    });

    test('SocketException -> message réseau', () {
      final e = mapError('test', const SocketException('no route'));
      expect(e.message, contains('connexion internet'));
    });

    test('TimeoutException -> message réseau', () {
      final e = mapError('test', TimeoutException('timeout'));
      expect(e.message, contains('connexion internet'));
    });

    test('AppException existante est renvoyée telle quelle', () {
      const original = AppException('Message métier spécifique');
      final e = mapError('test', original);
      expect(identical(e, original), isTrue);
    });

    test('erreur inconnue -> message générique', () {
      final e = mapError('test', Exception('boom'));
      expect(e.message, "Une erreur inattendue est survenue.");
    });
  });
}
