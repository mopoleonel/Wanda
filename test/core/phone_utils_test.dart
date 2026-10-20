import 'package:flutter_test/flutter_test.dart';
import 'package:wanda/core/utils/phone_utils.dart';

void main() {
  group('normalizePhone', () {
    test('numéro local camerounais -> +237', () {
      expect(normalizePhone('699 00 00 01'), '+237699000001');
    });

    test('format international avec +', () {
      expect(normalizePhone('+237 699-000-001'), '+237699000001');
    });

    test('préfixe 00', () {
      expect(normalizePhone('00237699000001'), '+237699000001');
    });

    test('indicatif sans + n\'est pas doublé', () {
      expect(normalizePhone('237699000001'), '+237699000001');
    });

    test('autre pays avec +', () {
      expect(normalizePhone('+33 6 12 34 56 78'), '+33612345678');
    });

    test('entrées invalides -> null', () {
      expect(normalizePhone(''), isNull);
      expect(normalizePhone('abc'), isNull);
      expect(normalizePhone('+12'), isNull);
    });
  });
}
