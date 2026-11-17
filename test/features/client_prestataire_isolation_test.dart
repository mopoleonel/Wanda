import 'package:flutter_test/flutter_test.dart';
import 'package:wanda/core/error/app_exception.dart';
import 'package:wanda/core/error/error_mapper.dart';
import 'package:wanda/core/api/api_client.dart';

void main() {
  group('Isolation et règles de sécurité Client vs Prestataire', () {
    test(
        'Tentative du client d\'accepter ou de terminer sa propre demande -> TRANSITION_INTERDITE',
        () {
      final exc = mapError(
        'SollicitationRepository.updateStatus',
        const ApiException('refus', code: 'TRANSITION_INTERDITE', statut: 409),
      );
      expect(exc, isA<AppException>());
      expect(
          exc.message, "Cette action n'est plus possible pour cette demande.");
    });

    test(
        'Tentative du client de modifier le prix_total directement -> PRIX_PROTEGE',
        () {
      final exc = mapError(
        'SollicitationRepository.update',
        const ApiException('refus', code: 'PRIX_PROTEGE', statut: 409),
      );
      expect(exc, isA<AppException>());
      expect(exc.message, "Le prix d'une demande ne peut pas être modifié.");
    });

    test(
        'Tentative du prestataire d\'annuler ou d\'archiver une mission -> TRANSITION_INTERDITE',
        () {
      final exc = mapError(
        'SollicitationRepository.updateStatus',
        const ApiException('refus', code: 'TRANSITION_INTERDITE', statut: 409),
      );
      expect(
          exc.message, "Cette action n'est plus possible pour cette demande.");
    });

    test(
        'Ajustement impossible si la mission n\'est pas acceptée -> AJUSTEMENT_IMPOSSIBLE',
        () {
      final exc = mapError(
        'DemandeRepository.demanderAjustement',
        const ApiException('refus', code: 'AJUSTEMENT_IMPOSSIBLE', statut: 409),
      );
      expect(exc.message,
          "Un ajustement n'est possible que sur une mission confirmée.");
    });

    test(
        'Ajustement avec 0 min et 0 produits supplémentaires -> AJUSTEMENT_VIDE',
        () {
      final exc = mapError(
        'DemandeRepository.demanderAjustement',
        const ApiException('refus', code: 'AJUSTEMENT_VIDE', statut: 409),
      );
      expect(exc.message, 'Indiquez le temps ou les produits en plus.');
    });

    test(
        'Tentative de double ajustement en attente -> AJUSTEMENT_DEJA_EN_ATTENTE',
        () {
      final exc = mapError(
        'DemandeRepository.demanderAjustement',
        const ApiException('refus',
            code: 'AJUSTEMENT_DEJA_EN_ATTENTE', statut: 409),
      );
      expect(exc.message, 'Un ajustement attend déjà la réponse du client.');
    });

    test('Tentative de double réponse à un ajustement -> DEJA_REPONDU', () {
      final exc = mapError(
        'DemandeRepository.repondreAjustement',
        const ApiException('refus', code: 'DEJA_REPONDU', statut: 409),
      );
      expect(exc.message, 'Vous avez déjà répondu à cet ajustement.');
    });

    test(
        'Pointage de passage sur prestation ponctuelle ou non acceptée -> PASSAGE_IMPOSSIBLE',
        () {
      final exc = mapError(
        'DemandeRepository.pointerPassage',
        const ApiException('refus', code: 'PASSAGE_IMPOSSIBLE', statut: 409),
      );
      expect(exc.message,
          'Le pointage est possible seulement sur un abonnement confirmé.');
    });

    test('Double pointage de passage le même jour -> PASSAGE_DEJA_POINTE', () {
      final exc = mapError(
        'DemandeRepository.pointerPassage',
        const ApiException('refus', code: 'PASSAGE_DEJA_POINTE', statut: 409),
      );
      expect(exc.message, "Le passage d'aujourd'hui est déjà pointé.");
    });

    test(
        'Tentative d\'utiliser la photo d\'un autre utilisateur -> PHOTO_INVALIDE',
        () {
      final exc = mapError(
        'DemandeRepository.creer',
        const ApiException('refus', code: 'PHOTO_INVALIDE', statut: 409),
      );
      expect(
          exc.message, "Photo non valide : reprenez-la depuis l'application.");
    });

    test(
        'Modification d\'identité alors que la certification est validée -> IDENTITE_FIGEE',
        () {
      final exc = mapError(
        'ProfileRepository.updateParticulierInfo',
        const ApiException('refus', code: 'IDENTITE_FIGEE', statut: 409),
      );
      expect(exc.message, contains('figées'));
    });

    test('Double avis pour une même sollicitation -> AVIS_DEJA_DONNE', () {
      final exc = mapError(
        'AvisRepository.create',
        const ApiException('refus', code: 'AVIS_DEJA_DONNE', statut: 409),
      );
      expect(exc.message, 'Vous avez déjà donné votre avis sur cette mission.');
    });

    test('Violation de contrainte unique sur avis -> avis_sollicitation_unique',
        () {
      final exc = mapError(
        'AvisRepository.create',
        const ApiException('refus', code: 'AVIS_DEJA_DONNE', statut: 409),
      );
      expect(exc.message, 'Vous avez déjà donné votre avis sur cette mission.');
    });
  });
}
