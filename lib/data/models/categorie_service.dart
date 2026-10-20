/// Les services ménagers à domicile proposés par WANDA.
///
/// Le [code] est la valeur enregistrée en base (`particuliers.services`,
/// `sollicitations.service`, table `tarifs`) : il ne change jamais. Les
/// libellés, eux, peuvent évoluer.
enum CategorieService {
  menage('menage', 'Ménage et nettoyage', 'Ménage',
      'Ménage régulier, grand ménage, après déménagement ou travaux, vitres, canapés et tapis'),
  linge('linge', 'Linge', 'Linge', 'Lessive et repassage'),
  dechets('dechets', 'Ramassage des poubelles', 'Déchets',
      'Vos poubelles sorties et emportées, chez vous'),
  nuisibles('nuisibles', 'Lutte contre les nuisibles', 'Nuisibles',
      'Désinsectisation, dératisation');

  const CategorieService(this.code, this.libelle, this.court, this.detail);

  /// Valeur stockée en base.
  final String code;

  /// Libellé complet (titres, récapitulatifs).
  final String libelle;

  /// Libellé court (onglets, étiquettes).
  final String court;

  /// Ce que couvre le service, en une ligne.
  final String detail;

  static CategorieService? fromCode(String? code) {
    for (final c in values) {
      if (c.code == code) return c;
    }
    return null;
  }

  /// Codes valides seulement, sans doublon, dans l'ordre de [values].
  static List<String> codesValides(Iterable<Object?> codes) {
    final set = codes.whereType<String>().toSet();
    return [
      for (final c in values)
        if (set.contains(c.code)) c.code,
    ];
  }
}
