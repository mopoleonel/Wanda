import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wanda/core/api/api_client.dart';
import 'package:wanda/core/error/app_exception.dart';
import 'package:wanda/core/error/error_mapper.dart';

void main() {
  group('mapError', () {
    test(
        "message du serveur affiché tel quel quand l'app n'en a pas de meilleur",
        () {
      final e = mapError(
          'test',
          const ApiException('Code incorrect.',
              code: 'CODE_INVALIDE', statut: 400));
      expect(e.message, 'Code incorrect.');
      expect((e as ApiException).code, 'CODE_INVALIDE');
    });

    test('trop de demandes de code : message du serveur', () {
      final e = mapError(
          'test',
          const ApiException(
              'Trop de demandes : réessayez dans quelques minutes.',
              code: 'TROP_DE_DEMANDES',
              statut: 429));
      expect(e.message, contains('Trop de demandes'));
    });

    test('client HTTP sans réseau -> message réseau', () {
      final e = mapError('test', http.ClientException('Connection refused'));
      expect(e.message, contains('connexion internet'));
    });

    test("refus métier de l'API traduits (prix protégé, ajustement…)", () {
      expect(
          mapError(
                  't',
                  const ApiException('refus',
                      code: 'PRIX_PROTEGE', statut: 409))
              .message,
          "Le prix d'une demande ne peut pas être modifié.");
      expect(
          mapError(
                  't',
                  const ApiException('refus',
                      code: 'AJUSTEMENT_DEJA_EN_ATTENTE', statut: 409))
              .message,
          contains('attend déjà'));
      expect(
          mapError(
                  't',
                  const ApiException('refus',
                      code: 'PRESTATAIRE_INDISPONIBLE', statut: 409))
              .message,
          contains("n'est plus disponible"));
      expect(
          mapError(
                  't',
                  const ApiException('refus',
                      code: 'IDENTITE_FIGEE', statut: 409))
              .message,
          contains('figées'));
      expect(
          mapError(
                  't',
                  const ApiException('refus',
                      code: 'PROFIL_INCOMPLET', statut: 409))
              .message,
          contains('Complétez votre profil'));
      expect(
          mapError(
                  't',
                  const ApiException('refus',
                      code: 'AVIS_DEJA_DONNE', statut: 409))
              .message,
          contains('déjà donné votre avis'));
      expect(
          mapError(
                  't',
                  const ApiException('refus',
                      code: 'DOCUMENT_DEJA_UTILISE', statut: 409))
              .message,
          contains('déjà associée'));
      expect(
          mapError(
                  't',
                  const ApiException('refus',
                      code: 'CONSENTEMENT_REQUIS', statut: 409))
              .message,
          contains('traitement des pièces'));
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
