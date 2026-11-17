/// Indicatif utilisé quand l'utilisateur saisit un numéro local (Cameroun).
const String kDefaultCountryCode = '237';

/// Normalise un numéro saisi par l'utilisateur au format international
/// E.164 (`+2376XXXXXXXX`) attendu par l'API WANDA / WhatsApp.
///
/// Accepte : `699 00 00 01`, `+237 699000001`, `00237699000001`,
/// `237699000001`. Retourne `null` si le numéro est manifestement invalide.
String? normalizePhone(String input,
    {String defaultCountryCode = kDefaultCountryCode}) {
  var value = input.replaceAll(RegExp(r'[\s\-\.\(\)]'), '');
  if (value.isEmpty) return null;

  if (value.startsWith('00')) {
    value = '+${value.substring(2)}';
  }

  String digits;
  if (value.startsWith('+')) {
    digits = value.substring(1);
  } else if (value.startsWith(defaultCountryCode) &&
      value.length > defaultCountryCode.length + 8) {
    digits = value;
  } else {
    digits = '$defaultCountryCode$value';
  }

  if (!RegExp(r'^[1-9]\d{7,14}$').hasMatch(digits)) return null;
  return '+$digits';
}
