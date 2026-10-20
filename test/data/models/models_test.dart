import 'package:flutter_test/flutter_test.dart';
import 'package:wanda/data/models/avis_prestataire.dart';
import 'package:wanda/data/models/particulier.dart';
import 'package:wanda/data/models/signalement.dart';
import 'package:wanda/data/models/sollicitation.dart';

void main() {
  group('Particulier.fromMap', () {
    test('parse une ligne complète', () {
      final p = Particulier.fromMap({
        'id': 'u1',
        'nom': 'Fouda',
        'prenom': 'Jean',
        'telephone': '699000000',
        'services': ['menage', 'Plombier', 'linge', 'menage'],
        'photo_pro_url': 'https://x/y.jpg',
        'is_available': true,
        'latitude': 3.848,
        'longitude': 11.502,
        'abonnement_expire_at':
            DateTime.now().add(const Duration(days: 5)).toIso8601String(),
        'type_abonnement': 'ESSAI',
        'essai_utilise': true,
      });

      expect(p.id, 'u1');
      // Codes inconnus (anciens métiers) et doublons écartés.
      expect(p.services, ['menage', 'linge']);
      expect(p.isAvailable, isTrue);
      expect(p.latitude, closeTo(3.848, 0.0001));
      expect(p.hasValidSubscription, isTrue);
    });

    test('gère les champs manquants sans planter', () {
      final p = Particulier.fromMap({'id': 'u2'});
      expect(p.nom, '');
      expect(p.isAvailable, isFalse);
      expect(p.latitude, isNull);
      expect(p.hasValidSubscription, isFalse);
    });

    test('abonnement expiré n\'est pas valide', () {
      final p = Particulier.fromMap({
        'id': 'u3',
        'abonnement_expire_at':
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      });
      expect(p.hasValidSubscription, isFalse);
    });
  });

  group('Signalement.fromMap', () {
    test('parse les coordonnées même si envoyées en string', () {
      final s = Signalement.fromMap({
        'id': 1,
        'type_probleme': "Fuite d'eau",
        'image_url': 'https://x/img.jpg',
        'latitude': '3.848',
        'longitude': '11.502',
        'statut': 'en_attente',
      });
      expect(s.id, '1');
      expect(s.latitude, closeTo(3.848, 0.0001));
      expect(s.longitude, closeTo(11.502, 0.0001));
    });
  });

  group('Sollicitation.fromMap', () {
    test('parse un expert imbriqué', () {
      final s = Sollicitation.fromMap({
        'id': 42,
        'prestataire_id': 'p1',
        'citoyen_id': 'c1',
        'nom_citoyen': 'Ateba',
        'numero_citoyen': '699111222',
        'statut': 'accepte',
        'expert': {
          'nom': 'Mbarga',
          'prenom': 'Paul',
          'service_propose': 'Électricien',
        },
      });
      expect(s.expert, isNotNull);
      expect(s.expert!.nom, 'Mbarga');
      expect(s.statut, 'accepte');
    });

    test('expert absent reste null sans erreur', () {
      final s = Sollicitation.fromMap({
        'id': 43,
        'prestataire_id': 'p1',
        'citoyen_id': 'c1',
        'numero_citoyen': '699111222',
        'statut': 'en_attente',
      });
      expect(s.expert, isNull);
    });
  });

  group('RatingSummary', () {
    test('empty a une moyenne de 0 et count de 0', () {
      expect(RatingSummary.empty.average, 0);
      expect(RatingSummary.empty.count, 0);
    });
  });
}
