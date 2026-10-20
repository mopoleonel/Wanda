import 'package:flutter_test/flutter_test.dart';
import 'package:wanda/core/identity/cni_parser.dart';

/// Construit une MRZ TD1 valide (chiffres de contrôle calculés) pour tester.
List<String> _mrz({
  String numero = '123456789',
  String naissance = '900312',
  String expiration = '301231',
  String sexe = 'M',
  String noms = 'NKENG<<PAUL<ARMAND',
}) {
  String d(String f) => CniParser.checkDigit(f).toString();
  final l1 = 'IDCMR$numero${d(numero)}'.padRight(30, '<');
  final l2 = '$naissance${d(naissance)}$sexe$expiration${d(expiration)}CMR'
      .padRight(29, '<');
  final l3 = noms.padRight(30, '<');
  return [l1, '${l2}0', l3];
}

void main() {
  group('Chiffre de contrôle ICAO', () {
    test('exemple de référence ICAO 9303', () {
      // Exemple officiel : « L898902C3 » -> 6.
      expect(CniParser.checkDigit('L898902C3'), 6);
      expect(CniParser.checkDigit('740812'), 2);
    });
  });

  group('MRZ du verso', () {
    test('lit nom, prénoms, dates et valide les contrôles', () {
      final mrz = CniParser.parseMrz(_mrz().join('\n'))!;
      expect(mrz.nom, 'NKENG');
      expect(mrz.prenoms, 'PAUL ARMAND');
      expect(mrz.numeroDocument, '123456789');
      expect(mrz.dateNaissance, DateTime(1990, 3, 12));
      expect(mrz.dateExpiration, DateTime(2030, 12, 31));
      expect(mrz.sexe, 'M');
      expect(mrz.isValid, isTrue);
      expect(mrz.isExpired, isFalse);
    });

    test('corrige les confusions OCR (O pour 0) dans les champs numériques',
        () {
      final lines = _mrz();
      // L'OCR lit « 9O0312 » au lieu de « 900312 ».
      lines[1] = lines[1].replaceFirst('900312', '9O0312');
      final mrz = CniParser.parseMrz(lines.join('\n'))!;
      expect(mrz.naissanceValide, isTrue);
      expect(mrz.dateNaissance, DateTime(1990, 3, 12));
    });

    test('détecte une lecture fausse grâce aux chiffres de contrôle', () {
      final lines = _mrz();
      lines[0] = lines[0].replaceFirst('123456789', '123456788');
      final mrz = CniParser.parseMrz(lines.join('\n'))!;
      expect(mrz.numeroValide, isFalse);
      expect(mrz.isValid, isFalse);
    });

    test('carte expirée', () {
      final mrz = CniParser.parseMrz(_mrz(expiration: '200101').join('\n'))!;
      expect(mrz.isExpired, isTrue);
    });

    test('tolère le bruit OCR autour de la MRZ', () {
      final text = [
        'AUTORITE / AUTHORITY',
        'DGSN',
        ..._mrz().map((l) => l.replaceAll('<', ' < ').replaceAll('  ', ' ')),
      ].join('\n');
      expect(CniParser.parseMrz(text)?.nom, 'NKENG');
    });

    test('aucun MRZ -> null', () {
      expect(CniParser.parseMrz('REPUBLIQUE DU CAMEROUN\nNOM'), isNull);
    });
  });

  group('Recto', () {
    const recto = '''
REPUBLIQUE DU CAMEROUN
REPUBLIC OF CAMEROON
CARTE NATIONALE D'IDENTITE
NOM/SURNAME
NOMO
PRENOMS/GIVEN NAMES
SARAH ESTELLE
DATE DE NAISSANCE/DATE OF BIRTH
12.03.1990
LIEU DE NAISSANCE/PLACE OF BIRTH
YAOUNDE
SEXE/SEX
F
''';

    test('extrait les champs utiles', () {
      final f = CniParser.parseFront(recto);
      expect(f.looksLikeCameroonId, isTrue);
      expect(f.nom, 'NOMO'); // « NOMO » n'est pas pris pour un libellé
      expect(f.prenoms, 'SARAH ESTELLE');
      expect(f.dateNaissance, DateTime(1990, 3, 12));
      expect(f.lieuNaissance, 'YAOUNDE');
      expect(f.sexe, 'F');
      expect(f.hasNames, isTrue);
    });

    test('valeur manquante -> null (pas le libellé suivant)', () {
      final f = CniParser.parseFront(
          'REPUBLIQUE DU CAMEROUN\nNOM/SURNAME\nPRENOMS/GIVEN NAMES\nPAUL');
      expect(f.nom, isNull);
      expect(f.prenoms, 'PAUL');
      expect(f.hasNames, isFalse);
    });

    test('un autre document n\'est pas reconnu comme CNI camerounaise', () {
      expect(
          CniParser.parseFront('PERMIS DE CONDUIRE\nNOM\nDUPONT')
              .looksLikeCameroonId,
          isFalse);
    });
  });

  test('ressemblance de noms tolérante aux accents et à l\'ordre', () {
    expect(CniParser.nameSimilarity('Sarah Estelle', 'ESTELLE SARAH'), 1);
    expect(CniParser.nameSimilarity('Hélène', 'HELENE'), 1);
    expect(CniParser.nameSimilarity('PAUL', 'JEAN'), 0);
  });
}
