import 'package:flutter_test/flutter_test.dart';
import 'package:wanda/data/models/categorie_service.dart';
import 'package:wanda/data/models/demande_menage.dart';
import 'package:wanda/data/pricing/tarification.dart';

/// Cas partagés avec le contrôle de la migration SQL 009 (même entrée, même
/// prix attendu) : si l'un change, l'autre doit changer aussi.
class _Cas {
  final String nom;
  final DemandeMenage demande;
  final int minutes, mainOeuvre, produits, prixPassage, passages, prixTotal;
  const _Cas(this.nom, this.demande,
      {required this.minutes,
      required this.mainOeuvre,
      required this.produits,
      required this.prixPassage,
      required this.passages,
      required this.prixTotal});
}

const _menage = CategorieService.menage;

final _cas = [
  const _Cas(
    'ménage simple : 2 chambres, salon, cuisine, douche',
    DemandeMenage(service: _menage, reponses: {
      Q.chambres: 2, Q.salons: 1, Q.cuisines: 1, Q.doucheWc: 1, //
      Q.etat: 'normal',
    }),
    minutes: 175, mainOeuvre: 3500, produits: 0, //
    prixPassage: 4500, passages: 1, prixTotal: 4500,
  ),
  const _Cas(
    'ménage sale, vitres, frigo, produits apportés',
    DemandeMenage(service: _menage, produitsFournis: true, reponses: {
      Q.chambres: 3, Q.salons: 1, Q.cuisines: 1, Q.doucheWc: 2, //
      Q.vitres: true, Q.frigo: true, Q.four: false, Q.etat: 'sale',
    }),
    minutes: 357, mainOeuvre: 7140, produits: 1500, //
    prixPassage: 9700, passages: 1, prixTotal: 9700,
  ),
  const _Cas(
    'ménage très sale, abonnement hebdomadaire',
    DemandeMenage(
        service: _menage,
        formule: Formule.abonnement,
        frequence: Frequence.hebdomadaire,
        reponses: {
          Q.chambres: 1, Q.salons: 1, Q.cuisines: 1, Q.doucheWc: 1, //
          Q.etat: 'tres_sale',
        }),
    minutes: 218, mainOeuvre: 4360, produits: 0, //
    prixPassage: 5400, passages: 4, prixTotal: 21600,
  ),
  const _Cas(
    'linge : 2 paniers délicats, 10 pièces à repasser, lessive apportée',
    DemandeMenage(
        service: CategorieService.linge,
        produitsFournis: true,
        reponses: {
          Q.paniers: 2, Q.drapsDelicats: true, Q.repassage: true, //
          Q.piecesRepassage: 10,
        }),
    minutes: 150, mainOeuvre: 3000, produits: 1000, //
    prixPassage: 5000, passages: 1, prixTotal: 5000,
  ),
  const _Cas(
    'déchets : 6 sacs par semaine en 2 passages, 3e étage, 50 m',
    DemandeMenage(
        service: CategorieService.dechets,
        formule: Formule.abonnement,
        frequence: Frequence.hebdomadaire,
        reponses: {
          Q.sacs: 6,
          Q.passagesSemaine: 2,
          Q.etage: 3,
          Q.distanceBac: '50',
        }),
    minutes: 26, mainOeuvre: 520, produits: 0, //
    prixPassage: 1600, passages: 8, prixTotal: 12800,
  ),
  const _Cas(
    'déchets : un sac au rez-de-chaussée = passage minimum',
    DemandeMenage(service: CategorieService.dechets, reponses: {
      Q.sacs: 1,
      Q.etage: 0,
      Q.distanceBac: '10',
    }),
    minutes: 15, mainOeuvre: 300, produits: 0, //
    prixPassage: 1300, passages: 1, prixTotal: 1300,
  ),
  const _Cas(
    'nuisibles : punaises, 3 pièces, infestation forte',
    DemandeMenage(
        service: CategorieService.nuisibles,
        produitsFournis: true,
        reponses: {
          Q.nuisible: 'punaises',
          Q.pieces: 3,
          Q.infestation: 'forte'
        }),
    minutes: 60, mainOeuvre: 1200, produits: 18000, //
    prixPassage: 20200, passages: 1, prixTotal: 20200,
  ),
  const _Cas(
    'nuisibles : cafards, 1 pièce, faible, abonnement mensuel',
    DemandeMenage(
        service: CategorieService.nuisibles,
        produitsFournis: true,
        formule: Formule.abonnement,
        frequence: Frequence.mensuel,
        reponses: {
          Q.nuisible: 'cafards',
          Q.pieces: 1,
          Q.infestation: 'faible'
        }),
    minutes: 20, mainOeuvre: 400, produits: 1500, //
    prixPassage: 2900, passages: 1, prixTotal: 2900,
  ),
];

void main() {
  group('calculerPrix — cas partagés avec SQL 009', () {
    for (final c in _cas) {
      test(c.nom, () {
        final e = calculerPrix(c.demande);
        expect(e.minutes, c.minutes, reason: 'minutes');
        expect(e.mainOeuvre, c.mainOeuvre, reason: "main d'œuvre");
        expect(e.deplacement, 1000, reason: 'déplacement');
        expect(e.produits, c.produits, reason: 'produits');
        expect(e.prixPassage, c.prixPassage, reason: 'prix par passage');
        expect(e.passages, c.passages, reason: 'passages');
        expect(e.prixTotal, c.prixTotal, reason: 'prix total');
      });
    }
  });

  group('règles', () {
    test('prix toujours arrondi à la centaine supérieure', () {
      for (final c in _cas) {
        expect(calculerPrix(c.demande).prixTotal % 100, 0, reason: c.nom);
      }
      expect(arrondiCentaine(4420), 4500);
      expect(arrondiCentaine(4500), 4500);
      expect(arrondiCentaine(0), 0);
    });

    test('la majoration d\'état ne porte que sur le temps', () {
      final normal = DemandeMenage.initiale(_menage);
      final tresSale = normal.avec(Q.etat, 'tres_sale');
      expect(calculerPrix(tresSale).minutes,
          (calculerPrix(normal).minutes * 150 + 99) ~/ 100);
      expect(calculerPrix(tresSale).produits, 0);
    });

    test('produits apportés : ajoutés seulement si demandés', () {
      final sans = DemandeMenage.initiale(_menage);
      final avec = sans.copyWith(produitsFournis: true);
      expect(calculerPrix(avec).prixPassage - calculerPrix(sans).prixPassage,
          1500);
    });

    test('nuisibles : produits toujours fournis, impossible de les retirer',
        () {
      final d = DemandeMenage.initiale(CategorieService.nuisibles)
          .copyWith(produitsFournis: false);
      expect(d.produitsFournis, isTrue);
      expect(d.produitsModifiables, isFalse);
    });

    test('nuisibles : le produit pèse plus que le temps', () {
      final e = calculerPrix(_cas[6].demande);
      expect(e.produits, greaterThan(e.mainOeuvre));
    });

    test('déchets : les passages par semaine ne comptent qu\'en hebdomadaire',
        () {
      const ponctuel = DemandeMenage(
          service: CategorieService.dechets,
          reponses: {Q.sacs: 6, Q.passagesSemaine: 3, Q.distanceBac: '10'});
      expect(calculerPrix(ponctuel).passages, 1);
      expect(calculerPrix(ponctuel).minutes, 6 * 5 + 1);
    });

    test('abonnement mensuel : un passage par mois', () {
      final d = DemandeMenage.initiale(_menage)
          .copyWith(formule: Formule.abonnement, frequence: Frequence.mensuel);
      final e = calculerPrix(d);
      expect(e.passages, 1);
      expect(e.prixTotal, e.prixPassage);
    });

    test('remise abonnement lue dans les tarifs (0 % par défaut)', () {
      final tarifs = Tarifs.depuisLignes([
        {'service': 'global', 'cle': 'remise_abonnement', 'valeur': 10},
      ]);
      final e = calculerPrix(_cas[2].demande, tarifs);
      // 4 × 5 400 = 21 600, −10 % = 19 440, arrondi = 19 500.
      expect(e.prixTotal, 19500);
      expect(calculerPrix(_cas[0].demande, tarifs).prixTotal, 4500,
          reason: 'pas de remise sur une demande ponctuelle');
    });

    test('tarifs modifiés en base : pris en compte, le reste par défaut', () {
      final tarifs = Tarifs.depuisLignes([
        {'service': 'global', 'cle': 'tarif_horaire', 'valeur': 1500},
        {'service': 'menage', 'cle': 'chambre', 'valeur': 35.0},
        {'service': null, 'cle': 'x', 'valeur': 1},
      ]);
      final e = calculerPrix(_cas[0].demande, tarifs);
      expect(e.minutes, 185);
      expect(e.mainOeuvre, (185 * 1500 + 30) ~/ 60);
      expect(e.deplacement, 1000);
    });

    test('quantités nulles ou négatives sans effet, minimum un panier', () {
      const d = DemandeMenage(
          service: CategorieService.linge, reponses: {Q.paniers: 0});
      expect(calculerPrix(d).minutes, 40);
    });
  });

  group('affichage', () {
    test('montants au format français, espaces insécables', () {
      expect(fcfa(5400), '5 400 FCFA');
      expect(fcfa(950), '950 FCFA');
      expect(fcfa(1234567), '1 234 567 FCFA');
    });

    test('durées lisibles', () {
      expect(duree(45), '45 min');
      expect(duree(60), '1 h');
      expect(duree(175), '2 h 55');
      expect(duree(125), '2 h 05');
    });

    test('détail du prix lisible, pluriels corrects', () {
      final e = calculerPrix(_cas[3].demande);
      final libelles = e.lignes.map((l) => l.libelle).toList();
      expect(libelles, contains('2 paniers × 40 min'));
      expect(libelles, contains('10 pièces à repasser × 4 min'));
      expect(libelles, contains('Produits apportés'));
      final hebdo = calculerPrix(_cas[2].demande);
      expect(
          hebdo.lignes.map((l) => l.libelle), contains('4 passages par mois'));
    });
  });

  group('demande', () {
    test('réponses de départ par service', () {
      for (final s in CategorieService.values) {
        final d = DemandeMenage.initiale(s);
        expect(d.reponses, isNotEmpty, reason: s.code);
        expect(calculerPrix(d).prixTotal, greaterThan(0), reason: s.code);
      }
    });

    test('un abonnement sans rythme est incomplet', () {
      final d =
          DemandeMenage.initiale(_menage).copyWith(formule: Formule.abonnement);
      expect(d.formuleComplete, isFalse);
      expect(d.copyWith(frequence: Frequence.mensuel).formuleComplete, isTrue);
    });
  });
}
