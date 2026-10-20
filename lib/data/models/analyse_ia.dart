import 'categorie_service.dart';
import 'demande_menage.dart';

/// Résultat de l'Edge Function `analyze-demande-menage` (JSON normalisé
/// côté serveur, voir `normaliser`).
class AnalyseIa {
  /// Identifiant de l'analyse enregistrée (table analyses_ia), transmis à
  /// la création de la demande. Null si l'enregistrement a échoué.
  final String? id;
  final bool photosConformes;
  final String? raisonNonConforme;
  final int? quantiteMin;
  final int? quantiteMax;

  /// État (ménage) ou niveau d'infestation (nuisibles).
  final String? niveau;
  final String? nuisible;
  final double confiance;
  final List<String> incoherences;

  const AnalyseIa({
    this.id,
    this.photosConformes = true,
    this.raisonNonConforme,
    this.quantiteMin,
    this.quantiteMax,
    this.niveau,
    this.nuisible,
    this.confiance = 0,
    this.incoherences = const [],
  });

  factory AnalyseIa.fromMap(Map<String, dynamic> m, {String? id}) {
    final e = (m['estimation'] as Map?)?.cast<String, dynamic>() ?? const {};
    int? entier(Object? v) => v is num ? v.round() : null;
    return AnalyseIa(
      id: id,
      photosConformes: m['photos_conformes'] != false,
      raisonNonConforme: m['raison_non_conforme'] as String?,
      quantiteMin: entier(e['quantite_min']),
      quantiteMax: entier(e['quantite_max']),
      niveau: e['niveau'] as String?,
      nuisible: e['nuisible'] as String?,
      confiance: (m['confiance'] as num?)?.toDouble() ?? 0,
      incoherences: [
        for (final i in (m['incoherences'] as List?) ?? const [])
          if (i is String) i,
      ],
    );
  }

  /// En dessous, l'estimation est trop incertaine pour proposer une
  /// correction (elle reste affichée au prestataire comme indication).
  static const confianceMinimale = 0.5;
}

/// Correction proposée au client : sa demande, ajustée à ce que montrent les
/// photos. L'IA ne bloque jamais : le client peut garder sa déclaration.
class CorrectionIa {
  final String explication;
  final DemandeMenage corrigee;
  const CorrectionIa(this.explication, this.corrigee);
}

const _rangEtat = {'normal': 0, 'sale': 1, 'tres_sale': 2};
const _rangInfestation = {'faible': 0, 'moyenne': 1, 'forte': 2};
const _libelleNiveau = {
  'normal': 'normal',
  'sale': 'sale',
  'tres_sale': 'très sale',
  'faible': 'faible',
  'moyenne': 'moyenne',
  'forte': 'forte',
};

/// Compare l'estimation de l'IA à la déclaration du client. Propose une
/// correction seulement si l'IA voit NETTEMENT plus (niveau supérieur, ou
/// quantité au-delà de [seuilPourcent]) avec une confiance suffisante.
CorrectionIa? comparerAvecIa(DemandeMenage d, AnalyseIa a,
    {int seuilPourcent = 50}) {
  if (!a.photosConformes || a.confiance < AnalyseIa.confianceMinimale) {
    return null;
  }

  CorrectionIa? quantite(String cle, String unite) {
    final declare = d.entier(cle);
    final vu = a.quantiteMin;
    if (vu == null || vu <= 0) return null;
    if (vu * 100 <= declare * (100 + seuilPourcent)) return null;
    return CorrectionIa(
        'Les photos montrent au moins $vu $unite, vous en avez déclaré $declare.',
        d.avec(cle, vu));
  }

  CorrectionIa? niveau(String cle, Map<String, int> rangs, String quoi) {
    final declare = d.code(cle);
    final vu = a.niveau;
    final rd = rangs[declare], rv = rangs[vu];
    if (rd == null || rv == null || rv <= rd) return null;
    return CorrectionIa(
        'Les photos montrent $quoi ${_libelleNiveau[vu]}, vous avez indiqué '
        '« ${_libelleNiveau[declare]} ».',
        d.avec(cle, vu!));
  }

  return switch (d.service) {
    CategorieService.menage => niveau(Q.etat, _rangEtat, 'un logement'),
    CategorieService.linge => quantite(Q.paniers, 'paniers'),
    CategorieService.dechets => quantite(Q.sacs, 'sacs'),
    CategorieService.nuisibles =>
      niveau(Q.infestation, _rangInfestation, 'une infestation'),
  };
}
