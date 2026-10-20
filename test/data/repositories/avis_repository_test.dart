import 'package:flutter_test/flutter_test.dart';
import 'package:wanda/data/repositories/avis_repository.dart';

void main() {
  group('aggregateRatings', () {
    test('calcule la moyenne et le compte par prestataire', () {
      final result = aggregateRatings([
        {'prestataire_id': 'p1', 'note': 5},
        {'prestataire_id': 'p1', 'note': 3},
        {'prestataire_id': 'p2', 'note': 4},
      ]);

      expect(result['p1']!.average, closeTo(4.0, 0.001));
      expect(result['p1']!.count, 2);
      expect(result['p2']!.average, closeTo(4.0, 0.001));
      expect(result['p2']!.count, 1);
    });

    test('liste vide -> map vide', () {
      expect(aggregateRatings([]), isEmpty);
    });

    test('un seul avis donne la note elle-même comme moyenne', () {
      final result = aggregateRatings([
        {'prestataire_id': 'p1', 'note': 2},
      ]);
      expect(result['p1']!.average, 2.0);
      expect(result['p1']!.count, 1);
    });
  });
}
