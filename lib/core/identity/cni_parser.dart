/// Analyse du texte reconnu (OCR) sur une carte nationale d'identité
/// camerounaise.
///
/// - Verso : zone de lecture automatique (MRZ, format international TD1 :
///   3 lignes de 30 caractères). Ses chiffres de contrôle permettent de
///   vérifier que le numéro, la date de naissance et la date d'expiration
///   ont été lus sans erreur.
/// - Recto : libellés bilingues (« NOM/SURNAME », « PRÉNOMS/GIVEN NAMES »...)
///   suivis de leur valeur.
///
/// Tout est en Dart pur (aucune dépendance ML Kit) pour être testé
/// unitairement.
library;

/// Données extraites du recto.
class CniFront {
  final String? nom;
  final String? prenoms;
  final DateTime? dateNaissance;
  final String? lieuNaissance;
  final String? sexe;

  /// Le texte contient les mentions officielles d'une CNI camerounaise.
  final bool looksLikeCameroonId;

  const CniFront({
    this.nom,
    this.prenoms,
    this.dateNaissance,
    this.lieuNaissance,
    this.sexe,
    required this.looksLikeCameroonId,
  });

  bool get hasNames =>
      (nom ?? '').trim().isNotEmpty && (prenoms ?? '').trim().isNotEmpty;
}

/// Données extraites de la MRZ du verso.
class CniMrz {
  final String numeroDocument;
  final String nom;
  final String prenoms;
  final DateTime? dateNaissance;
  final DateTime? dateExpiration;
  final String sexe;
  final String nationalite;

  /// Chiffres de contrôle : numéro, naissance, expiration.
  final bool numeroValide;
  final bool naissanceValide;
  final bool expirationValide;

  const CniMrz({
    required this.numeroDocument,
    required this.nom,
    required this.prenoms,
    required this.dateNaissance,
    required this.dateExpiration,
    required this.sexe,
    required this.nationalite,
    required this.numeroValide,
    required this.naissanceValide,
    required this.expirationValide,
  });

  /// Lecture fiable : les trois chiffres de contrôle sont bons.
  bool get isValid => numeroValide && naissanceValide && expirationValide;

  bool get isExpired =>
      dateExpiration != null && dateExpiration!.isBefore(_today());
}

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

class CniParser {
  CniParser._();

  // ---------------------------------------------------------------- MRZ ---

  /// Chiffre de contrôle ICAO 9303 (pondérations 7, 3, 1).
  static int checkDigit(String field) {
    const weights = [7, 3, 1];
    var sum = 0;
    for (var i = 0; i < field.length; i++) {
      sum += _charValue(field[i]) * weights[i % 3];
    }
    return sum % 10;
  }

  static int _charValue(String c) {
    final code = c.codeUnitAt(0);
    if (code >= 48 && code <= 57) return code - 48; // 0-9
    if (code >= 65 && code <= 90) return code - 55; // A=10 ... Z=35
    return 0; // '<' et le reste
  }

  /// Corrige les confusions OCR courantes dans un champ numérique.
  static String _digits(String s) => s
      .replaceAll('O', '0')
      .replaceAll('Q', '0')
      .replaceAll('D', '0')
      .replaceAll('I', '1')
      .replaceAll('L', '1')
      .replaceAll('Z', '2')
      .replaceAll('S', '5')
      .replaceAll('B', '8')
      .replaceAll('G', '6');

  static bool _check(String field, String digit) {
    final d = int.tryParse(_digits(digit));
    return d != null && checkDigit(field) == d;
  }

  /// Date AAMMJJ. [future] : vrai pour une expiration (siècle à venir).
  static DateTime? _yymmdd(String raw, {required bool future}) {
    final s = _digits(raw);
    if (!RegExp(r'^\d{6}$').hasMatch(s)) return null;
    final yy = int.parse(s.substring(0, 2));
    final mm = int.parse(s.substring(2, 4));
    final dd = int.parse(s.substring(4, 6));
    if (mm < 1 || mm > 12 || dd < 1 || dd > 31) return null;
    final now = DateTime.now().year % 100;
    final century = future
        ? 2000
        : (yy > now ? 1900 : 2000); // naissance : jamais dans le futur
    return DateTime(century + yy, mm, dd);
  }

  /// Cherche une MRZ TD1 dans le texte reconnu du verso.
  static CniMrz? parseMrz(String recognizedText) {
    final candidates = recognizedText
        .toUpperCase()
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'\s'), '').replaceAll('«', '<'))
        .where((l) => l.length >= 25 && RegExp(r'^[A-Z0-9<]+$').hasMatch(l))
        .toList();

    for (var i = 0; i + 2 < candidates.length; i++) {
      final l1 = _pad(candidates[i]);
      final l2 = _pad(candidates[i + 1]);
      final l3 = _pad(candidates[i + 2]);
      if (!l1.startsWith('I') && !l1.startsWith('A') && !l1.startsWith('C')) {
        continue;
      }
      final result = _parseTd1(l1, l2, l3);
      if (result != null) return result;
    }
    return null;
  }

  static String _pad(String l) =>
      l.length >= 30 ? l.substring(0, 30) : l.padRight(30, '<');

  static CniMrz? _parseTd1(String l1, String l2, String l3) {
    // Ligne 1 : type (2) · pays (3) · numéro (9) · contrôle (1) · option (15)
    var numero = l1.substring(5, 14);
    final numeroCheck = l1.substring(14, 15);
    final option1 = l1.substring(15, 30);

    // Ligne 2 : naissance (6) · ctrl · sexe · expiration (6) · ctrl ·
    // nationalité (3) · option (11) · contrôle global
    final naissance = l2.substring(0, 6);
    final naissanceCheck = l2.substring(6, 7);
    final sexe = l2.substring(7, 8);
    final expiration = l2.substring(8, 14);
    final expirationCheck = l2.substring(14, 15);
    final nationalite = l2.substring(15, 18);

    var numeroValide = _check(numero, numeroCheck);
    // Numéro long : la suite est dans le champ optionnel (après un '<').
    if (numeroCheck == '<') {
      final rest = option1.split('<').first;
      if (rest.length > 1) {
        final full = numero + rest.substring(0, rest.length - 1);
        numeroValide = _check(full, rest[rest.length - 1]);
        numero = full;
      }
    }
    final naissanceValide = _check(_digits(naissance), naissanceCheck);
    final expirationValide = _check(_digits(expiration), expirationCheck);

    // Au moins une date lisible, sinon ce n'est pas une MRZ.
    final dn = _yymmdd(naissance, future: false);
    final de = _yymmdd(expiration, future: true);
    if (dn == null && de == null) return null;

    // Ligne 3 : NOM<<PRENOM<PRENOM2<<<<
    final parts = l3.split('<<');
    final nom = parts.first.replaceAll('<', ' ').trim();
    final prenoms = parts.length > 1
        ? parts.sublist(1).join(' ').replaceAll('<', ' ').trim()
        : '';
    if (nom.isEmpty) return null;

    return CniMrz(
      numeroDocument: numero.replaceAll('<', ''),
      nom: _clean(nom),
      prenoms: _clean(prenoms),
      dateNaissance: dn,
      dateExpiration: de,
      sexe: sexe == 'F' ? 'F' : (sexe == 'M' ? 'M' : ''),
      nationalite: nationalite.replaceAll('<', ''),
      numeroValide: numeroValide,
      naissanceValide: naissanceValide,
      expirationValide: expirationValide,
    );
  }

  // -------------------------------------------------------------- Recto ---

  static final _labelNom = RegExp(r'^(NOM|SURNAME)\b|NOM\s*/\s*SURNAME');
  static final _labelPrenoms =
      RegExp(r'PR[EÉ]NOMS?|GIVEN\s*NAMES?', caseSensitive: false);
  static final _labelNaissance =
      RegExp(r'DATE\s*DE\s*NAISSANCE|DATE\s*OF\s*BIRTH', caseSensitive: false);
  static final _labelLieu =
      RegExp(r'LIEU\s*DE\s*NAISSANCE|PLACE\s*OF\s*BIRTH', caseSensitive: false);
  static final _labelSexe = RegExp(r'^SEXE|/\s*SEX\b', caseSensitive: false);
  // Mots entiers seulement : un nom comme « NOMO » n'est pas un libellé.
  static final _anyLabel = RegExp(
      r'\bNOMS?\b|SURNAME|PR[EÉ]NOMS?\b|GIVEN\s*NAMES?|NAISSANCE|BIRTH|'
      r'\bSEXE?\b|TAILLE|HEIGHT|PROFESSION|OCCUPATION|SIGNATURE|'
      r'R[EÉ]PUBLIQUE|REPUBLIC|CAMEROUN|CAMEROON|IDENTIT[EÉ]|IDENTITY|'
      r'\bCARTE\b|\bCARD\b',
      caseSensitive: false);

  static CniFront parseFront(String recognizedText) {
    final lines = recognizedText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final upper = recognizedText.toUpperCase();
    final looksLikeId =
        (upper.contains('CAMEROUN') || upper.contains('CAMEROON')) &&
            (upper.contains('IDENTIT') ||
                upper.contains('IDENTITY') ||
                upper.contains('NOM') ||
                upper.contains('SURNAME'));

    String? valueAfter(RegExp label) {
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!label.hasMatch(line.toUpperCase())) continue;
        // Valeur sur la même ligne après « : » ?
        final colon = line.indexOf(':');
        if (colon >= 0 && colon < line.length - 2) {
          final v = line.substring(colon + 1).trim();
          if (v.isNotEmpty && !_anyLabel.hasMatch(v)) return v;
        }
        // Sinon : la ligne suivante, si ce n'est pas déjà un autre libellé.
        if (i + 1 < lines.length && !_anyLabel.hasMatch(lines[i + 1])) {
          return lines[i + 1];
        }
      }
      return null;
    }

    final naissanceRaw = valueAfter(_labelNaissance);
    return CniFront(
      nom: _cleanOrNull(valueAfter(_labelNom)),
      prenoms: _cleanOrNull(valueAfter(_labelPrenoms)),
      dateNaissance: naissanceRaw == null ? null : _parseDate(naissanceRaw),
      lieuNaissance: _cleanOrNull(valueAfter(_labelLieu)),
      sexe: _sexe(valueAfter(_labelSexe)),
      looksLikeCameroonId: looksLikeId,
    );
  }

  /// Dates du recto : « 12.03.1990 », « 12/03/1990 », « 12 03 1990 ».
  static DateTime? _parseDate(String raw) {
    final m = RegExp(r'(\d{1,2})[./\-\s](\d{1,2})[./\-\s](\d{4})')
        .firstMatch(_digits(raw.toUpperCase()));
    if (m == null) return null;
    final d = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final y = int.parse(m.group(3)!);
    if (mo < 1 || mo > 12 || d < 1 || d > 31 || y < 1900) return null;
    return DateTime(y, mo, d);
  }

  static String? _sexe(String? raw) {
    if (raw == null) return null;
    final u = raw.toUpperCase();
    if (u.startsWith('F')) return 'F';
    if (u.startsWith('M')) return 'M';
    return null;
  }

  static String? _cleanOrNull(String? s) {
    if (s == null) return null;
    final c = _clean(s);
    return c.isEmpty ? null : c;
  }

  /// Majuscules, sans chiffres ni ponctuation parasite.
  static String _clean(String s) => s
      .toUpperCase()
      .replaceAll(RegExp(r"[^A-ZÀ-ÖØ-Ý' \-]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // ------------------------------------------------------ Recoupement ---

  /// Ressemblance de deux noms (0..1), tolérante aux accents et à l'ordre.
  static double nameSimilarity(String a, String b) {
    String norm(String s) => s
        .toUpperCase()
        .replaceAll(RegExp('[ÀÂÄ]'), 'A')
        .replaceAll(RegExp('[ÉÈÊË]'), 'E')
        .replaceAll(RegExp('[ÎÏ]'), 'I')
        .replaceAll(RegExp('[ÔÖ]'), 'O')
        .replaceAll(RegExp('[ÙÛÜ]'), 'U')
        .replaceAll('Ç', 'C')
        .replaceAll(RegExp(r'[^A-Z ]'), ' ');
    final ta = norm(a).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();
    final tb = norm(b).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();
    if (ta.isEmpty || tb.isEmpty) return 0;
    final common = ta.intersection(tb).length;
    return common / (ta.length > tb.length ? ta.length : tb.length);
  }
}
