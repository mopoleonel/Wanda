import 'package:flutter_test/flutter_test.dart';
import 'package:wanda/data/models/analyse_ia.dart';
import 'package:wanda/data/models/categorie_service.dart';
import 'package:wanda/data/models/demande_menage.dart';
import 'package:wanda/data/models/sollicitation.dart';

AnalyseIa _ia(
        {int? min, String? niveau, double confiance = 0.8, bool ok = true}) =>
    AnalyseIa(
        quantiteMin: min,
        niveau: niveau,
        confiance: confiance,
        photosConformes: ok);

void main() {
  group('comparerAvecIa', () {
    final dechets =
        DemandeMenage.initiale(CategorieService.dechets).avec(Q.sacs, 2);

    test('déchets : nettement plus de sacs → correction proposée', () {
      final c = comparerAvecIa(dechets, _ia(min: 4));
      expect(c, isNotNull);
      expect(c!.corrigee.entier(Q.sacs), 4);
      expect(c.explication, contains('au moins 4 sacs'));
    });

    test('écart sous le seuil (+50 %) : rien à corriger', () {
      expect(comparerAvecIa(dechets, _ia(min: 3)), isNull);
      expect(comparerAvecIa(dechets, _ia(min: 1)), isNull);
    });

    test('ménage : état plus sale que déclaré → correction', () {
      final d = DemandeMenage.initiale(CategorieService.menage);
      final c = comparerAvecIa(d, _ia(niveau: 'tres_sale'));
      expect(c!.corrigee.code(Q.etat), 'tres_sale');
      expect(c.explication, contains('très sale'));
      expect(comparerAvecIa(d, _ia(niveau: 'normal')), isNull);
    });

    test('nuisibles : infestation plus forte → correction', () {
      final d = DemandeMenage.initiale(CategorieService.nuisibles)
          .avec(Q.infestation, 'faible');
      expect(
          comparerAvecIa(d, _ia(niveau: 'forte'))!.corrigee.code(Q.infestation),
          'forte');
    });

    test('linge : paniers', () {
      final d = DemandeMenage.initiale(CategorieService.linge);
      expect(comparerAvecIa(d, _ia(min: 3))!.corrigee.entier(Q.paniers), 3);
    });

    test('jamais de correction si l\'IA doute ou si les photos sont hors sujet',
        () {
      expect(comparerAvecIa(dechets, _ia(min: 9, confiance: 0.3)), isNull);
      expect(comparerAvecIa(dechets, _ia(min: 9, ok: false)), isNull);
    });

    test('le seuil vient des tarifs', () {
      expect(
          comparerAvecIa(dechets, _ia(min: 3), seuilPourcent: 20), isNotNull);
    });
  });

  test('AnalyseIa.fromMap lit le JSON normalisé du serveur', () {
    final a = AnalyseIa.fromMap({
      'photos_conformes': true,
      'estimation': {'quantite_min': 3, 'quantite_max': 4.6, 'niveau': null},
      'confiance': 0.72,
      'incoherences': ['Environ 4 sacs visibles, 2 déclarés', 12],
    }, id: 'a1');
    expect(a.id, 'a1');
    expect(a.quantiteMin, 3);
    expect(a.quantiteMax, 5);
    expect(a.confiance, closeTo(0.72, 1e-9));
    expect(a.incoherences, ['Environ 4 sacs visibles, 2 déclarés']);
  });

  group('Sollicitation.fromMap', () {
    test('demande ménagère complète', () {
      final s = Sollicitation.fromMap({
        'id': 'd1',
        'prestataire_id': 'p1',
        'citoyen_id': 'c1',
        'statut': 'refuse',
        'service': 'linge',
        'formule': 'abonnement',
        'frequence': 'hebdomadaire',
        'reponses': {'paniers': 2, 'repassage': true},
        'produits_fournis': true,
        'minutes_estimees': 120,
        'prix_passage': 5000,
        'prix_total': 20000,
        'photos': ['c1/d/1.jpg'],
        'ia_analyse': {'confiance': 0.9, 'incoherences': []},
        'date_souhaitee': '2026-10-21',
        'creneau': 'apres_midi',
        'motif_refus': 'Pas disponible ce jour-là',
      });
      expect(s.estDemandeMenage, isTrue);
      expect(s.service, CategorieService.linge);
      expect(s.formule, Formule.abonnement);
      expect(s.frequence, Frequence.hebdomadaire);
      expect(s.prixTotal, 20000);
      expect(s.photos, ['c1/d/1.jpg']);
      expect(s.analyseIa!.confiance, 0.9);
      expect(s.creneau, Creneau.apresMidi);
      expect(s.dateSouhaitee, DateTime(2026, 10, 21));
      expect(s.demande!.entier(Q.paniers), 2);
    });

    test('ancienne demande sans service : lisible, pas de prix', () {
      final s = Sollicitation.fromMap({
        'id': 7,
        'prestataire_id': 'p1',
        'citoyen_id': 'c1',
        'statut': 'accepte',
      });
      expect(s.estDemandeMenage, isFalse);
      expect(s.prixTotal, isNull);
      expect(s.demande, isNull);
      expect(s.formule, Formule.ponctuelle);
    });
  });
}
