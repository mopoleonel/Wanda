import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wanda/core/error/app_exception.dart';
import 'package:wanda/core/providers/repository_providers.dart';
import 'package:wanda/core/router/app_routes.dart';
import 'package:wanda/core/theme/app_theme.dart';
import 'package:wanda/data/models/avis_prestataire.dart';
import 'package:wanda/data/models/categorie_service.dart';
import 'package:wanda/data/models/citoyen.dart';
import 'package:wanda/data/models/demande_menage.dart';
import 'package:wanda/data/models/particulier.dart';
import 'package:wanda/data/pricing/tarification.dart';
import 'package:wanda/data/repositories/auth_repository.dart';
import 'package:wanda/data/repositories/avis_repository.dart';
import 'package:wanda/data/repositories/demande_repository.dart';
import 'package:wanda/data/repositories/prestataire_repository.dart';
import 'package:wanda/data/repositories/profile_repository.dart';
import 'package:wanda/features/demande/composants.dart';
import 'package:wanda/features/demande/demande_page.dart';

class _FakeTarifs extends Fake implements TarifRepository {
  @override
  Future<Tarifs> charger() async => Tarifs.defaut;
}

/// Le « serveur » : même calcul que l'app, sauf si on force un écart.
class _FakeDemandes extends Fake implements DemandeRepository {
  int? prixImpose;
  String? erreurCreation;
  final creees = <Map<String, Object?>>[];

  @override
  Future<EstimationPrix> prixServeur(DemandeMenage d) async {
    final e = calculerPrix(d);
    return prixImpose == null
        ? e
        : EstimationPrix(
            minutes: e.minutes,
            mainOeuvre: e.mainOeuvre,
            deplacement: e.deplacement,
            produits: e.produits,
            prixPassage: prixImpose!,
            passages: 1,
            prixTotal: prixImpose!);
  }

  @override
  Future<String> creer({
    required String prestataireId,
    required DemandeMenage demande,
    required List<String> photos,
    String? analyseId,
    required DateTime date,
    required Creneau creneau,
  }) async {
    if (erreurCreation != null) throw AppException(erreurCreation!);
    creees.add({
      'prestataire': prestataireId,
      'service': demande.service.code,
      'paniers': demande.entier(Q.paniers),
      'photos': photos,
      'creneau': creneau,
      'date': date,
    });
    return 'nouvelle';
  }
}

class _FakePrestataires extends Fake implements PrestataireRepository {
  List<Particulier> liste = const [];
  @override
  Future<List<Particulier>> disponiblesPour(String code) async => liste;
}

class _FakeAuth extends Fake implements AuthRepository {
  @override
  String? get currentUserId => 'c1';
}

class _FakeProfils extends Fake implements ProfileRepository {
  Citoyen citoyen = const Citoyen(
      citoyenId: 'c1',
      nom: 'Mbarga',
      prenom: 'Lucie',
      email: '',
      telephone: '+237677000000');
  String? nomEnregistre;

  @override
  Future<Citoyen?> fetchCitoyen(String id) async => citoyen;

  @override
  Future<void> updateCitoyen(Citoyen c) async => nomEnregistre = c.nom;
}

class _FakeAvis extends Fake implements AvisRepository {
  @override
  Future<Map<String, RatingSummary>> averagesForPrestataires(
          List<String> ids) async =>
      const {};
}

const _awa = Particulier(
    id: 'p2',
    nom: 'Ngo',
    prenom: 'Awa',
    telephone: '+237699000002',
    services: ['linge'],
    isAvailable: true,
    identiteVerifiee: true);
const _ben = Particulier(
    id: 'p3',
    nom: 'Eto',
    prenom: 'Ben',
    telephone: '+237699000003',
    services: ['linge'],
    isAvailable: true);

class _Harness {
  final demandes = _FakeDemandes();
  final prestataires = _FakePrestataires();
  final profils = _FakeProfils();
  Object? retour;

  Widget app(DemandeArgs args) {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                retour =
                    await context.push(AppRoutes.citoyenDemande, extra: args);
              },
              child: const Text('OUVRIR'),
            ),
          ),
        ),
      ),
      GoRoute(
          path: AppRoutes.citoyenDemande,
          builder: (_, state) =>
              DemandePage(args: state.extra! as DemandeArgs)),
    ]);
    return ProviderScope(
      overrides: [
        tarifRepositoryProvider.overrideWithValue(_FakeTarifs()),
        demandeRepositoryProvider.overrideWithValue(demandes),
        prestataireRepositoryProvider.overrideWithValue(prestataires),
        avisRepositoryProvider.overrideWithValue(_FakeAvis()),
        authRepositoryProvider.overrideWithValue(_FakeAuth()),
        profileRepositoryProvider.overrideWithValue(profils),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Laisse expirer la recherche de position (pas de GPS en test).
Future<void> _fin(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpWidget(const SizedBox());
}

Future<void> _ouvrir(WidgetTester tester, _Harness h, DemandeArgs args) async {
  await tester.pumpWidget(h.app(args));
  await tester.tap(find.text('OUVRIR'));
  await _settle(tester);
}

String _prix(int montant) => fcfa(montant);

final _boutonReserver = find.descendant(
    of: find.byType(BarrePrix), matching: find.text('Réserver'));

void main() {
  late _Harness h;
  setUp(() => h = _Harness());

  void grandEcran(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 2400);
    addTearDown(tester.view.reset);
  }

  testWidgets('Étape 1 : formule et questions sur le même écran',
      (tester) async {
    grandEcran(tester);
    await _ouvrir(tester, h, const DemandeArgs(CategorieService.menage));

    expect(find.text('Décrivez votre besoin'), findsOneWidget);
    expect(find.text('Ménage · étape 1 sur 3'), findsOneWidget);
    expect(find.text('Une fois'), findsOneWidget);
    expect(find.text('Chambres'), findsOneWidget);
    final unique =
        calculerPrix(DemandeMenage.initiale(CategorieService.menage));
    expect(find.text('≈ ${_prix(unique.prixTotal)}'), findsOneWidget);

    await tester.tap(find.text('Abonnement'));
    await tester.pump();
    expect(find.text('Chaque semaine'), findsOneWidget);
    expect(find.text('Estimation par mois'), findsOneWidget);
    expect(find.text('≈ ${_prix(unique.prixTotal * 4)}'), findsOneWidget);
  });

  testWidgets('Étape 1 : chaque compteur met le prix à jour en direct',
      (tester) async {
    grandEcran(tester);
    await _ouvrir(tester, h, const DemandeArgs(CategorieService.menage));

    final avant = calculerPrix(DemandeMenage.initiale(CategorieService.menage));
    // + 1 chambre : +30 min.
    await tester.tap(find.byTooltip('Plus').first);
    await tester.pump();
    final apres = calculerPrix(
        DemandeMenage.initiale(CategorieService.menage).avec(Q.chambres, 2));
    expect(apres.prixTotal, greaterThan(avant.prixTotal));
    expect(find.text('≈ ${_prix(apres.prixTotal)}'), findsOneWidget);

    // Logement très sale : +50 % de temps.
    await tester.ensureVisible(find.text('Très sale'));
    await tester.tap(find.text('Très sale'));
    await tester.pump();
    final sale = calculerPrix(DemandeMenage.initiale(CategorieService.menage)
        .avec(Q.chambres, 2)
        .avec(Q.etat, 'tres_sale'));
    expect(find.text('≈ ${_prix(sale.prixTotal)}'), findsOneWidget);
  });

  testWidgets('Ménage sans aucune pièce : on ne peut pas continuer',
      (tester) async {
    grandEcran(tester);
    await _ouvrir(tester, h, const DemandeArgs(CategorieService.menage));
    // Les 4 compteurs de pièces à zéro.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip('Moins').at(i));
      await tester.pump();
    }
    await tester.tap(find.text('Continuer'));
    await _settle(tester);
    expect(
        find.text('Indiquez au moins une pièce à nettoyer.'), findsOneWidget);
    expect(find.text('Décrivez votre besoin'), findsOneWidget);
  });

  testWidgets("Étape 2 : photos obligatoires, le retour revient à l'étape 1",
      (tester) async {
    grandEcran(tester);
    await _ouvrir(tester, h, const DemandeArgs(CategorieService.dechets));
    await tester.tap(find.text('Continuer'));
    await _settle(tester);

    expect(find.text('Ajoutez des photos'), findsOneWidget);
    expect(find.text('Photo'), findsOneWidget);
    expect(find.textContaining('Photographiez les sacs'), findsOneWidget);

    await tester.tap(find.byTooltip('Retour'));
    await _settle(tester);
    expect(find.text('Décrivez votre besoin'), findsOneWidget);
  });

  testWidgets(
      'Reprise après refus : récapitulatif au prix du serveur, choix d\'un '
      'autre prestataire, réservation', (tester) async {
    grandEcran(tester);
    h.prestataires.liste = [_awa, _ben];
    final reprise =
        DemandeMenage.initiale(CategorieService.linge).avec(Q.paniers, 3);
    await _ouvrir(
        tester,
        h,
        DemandeArgs(CategorieService.linge,
            reprise: reprise, photosEnvoyees: const ['c1/d/1.jpg']));

    expect(find.text('Vérifiez et réservez'), findsOneWidget);
    expect(find.text('3 paniers'), findsOneWidget);
    expect(find.text('1 photo jointe'), findsOneWidget);
    final prix = calculerPrix(reprise).prixTotal;
    expect(find.text('Prix fixé par WANDA'), findsOneWidget);
    expect(find.text(_prix(prix)), findsWidgets);

    // Deux prestataires : le bouton invite à choisir, sans erreur.
    expect(_boutonReserver, findsNothing);
    await tester.tap(find.text('Choisir'));
    await _settle(tester);
    expect(find.text('Touchez un prestataire dans la liste.'), findsOneWidget);
    expect(h.demandes.creees, isEmpty);

    await tester.tap(find.text('Ben Eto'));
    await tester.tap(find.text('Après-midi'));
    await tester.pump();
    await tester.tap(_boutonReserver);
    await _settle(tester);

    expect(h.demandes.creees.single, {
      'prestataire': 'p3',
      'service': 'linge',
      'paniers': 3,
      'photos': ['c1/d/1.jpg'],
      'creneau': Creneau.apresMidi,
      'date': h.demandes.creees.single['date'],
    });
    expect(h.retour, isTrue, reason: 'retour à « Mes demandes »');
    await _fin(tester);
  });

  testWidgets('Le prix affiché au récapitulatif est celui du serveur',
      (tester) async {
    grandEcran(tester);
    h.demandes.prixImpose = 9900;
    await _ouvrir(
        tester,
        h,
        DemandeArgs(CategorieService.linge,
            prestataire: _awa,
            reprise: DemandeMenage.initiale(CategorieService.linge),
            photosEnvoyees: const ['c1/d/1.jpg']));

    expect(find.text(_prix(9900)), findsWidgets);
    expect(find.text('Prix fixe'), findsOneWidget);
    // Prestataire déjà choisi depuis sa fiche : pas de liste.
    expect(find.text('Awa Ngo'), findsOneWidget);
    await _fin(tester);
  });

  testWidgets('Refus du serveur : message clair, on reste sur la page',
      (tester) async {
    grandEcran(tester);
    h.demandes.erreurCreation =
        "Ce prestataire n'est plus disponible pour ce service. Choisissez-en un autre.";
    await _ouvrir(
        tester,
        h,
        DemandeArgs(CategorieService.linge,
            prestataire: _awa,
            reprise: DemandeMenage.initiale(CategorieService.linge),
            photosEnvoyees: const ['c1/d/1.jpg']));
    await tester.tap(_boutonReserver);
    await _settle(tester);

    expect(find.textContaining("n'est plus disponible"), findsOneWidget);
    expect(find.text('Vérifiez et réservez'), findsOneWidget);
    expect(h.retour, isNull);
    await _fin(tester);
  });

  testWidgets('Client inscrit sans nom : demandé au récapitulatif, enregistré',
      (tester) async {
    grandEcran(tester);
    h.profils.citoyen = const Citoyen(
        citoyenId: 'c1',
        nom: '',
        prenom: '',
        email: '',
        telephone: '+237690000002');
    await _ouvrir(
        tester,
        h,
        DemandeArgs(CategorieService.linge,
            prestataire: _awa,
            reprise: DemandeMenage.initiale(CategorieService.linge),
            photosEnvoyees: const ['c1/d/1.jpg']));

    expect(find.text('Votre nom'), findsOneWidget);
    await tester.tap(_boutonReserver);
    await _settle(tester);
    expect(
        find.text('Indiquez votre nom pour le prestataire.'), findsOneWidget);
    expect(h.demandes.creees, isEmpty);

    await tester.enterText(find.widgetWithText(TextField, 'Nom'), 'Atangana');
    await tester.tap(_boutonReserver);
    await _settle(tester);
    expect(h.profils.nomEnregistre, 'Atangana');
    expect(h.demandes.creees, hasLength(1));
    await _fin(tester);
  });

  testWidgets(
      'Reprise : sans le prestataire qui a refusé, même jour et créneau',
      (tester) async {
    grandEcran(tester);
    h.prestataires.liste = [_awa, _ben];
    final apresDemain = DateTime.now().add(const Duration(days: 2));
    await _ouvrir(
        tester,
        h,
        DemandeArgs(CategorieService.linge,
            reprise: DemandeMenage.initiale(CategorieService.linge),
            photosEnvoyees: const ['c1/d/1.jpg'],
            exclu: 'p2',
            date: apresDemain,
            creneau: Creneau.apresMidi));

    expect(find.text('Awa Ngo'), findsNothing);
    expect(find.text('Ben Eto'), findsOneWidget);
    await tester.tap(find.text('Réserver').last);
    await _settle(tester);
    final c = h.demandes.creees.single;
    expect(c['prestataire'], 'p3');
    expect(c['creneau'], Creneau.apresMidi);
    expect((c['date'] as DateTime).day, apresDemain.day);
    await _fin(tester);
  });

  testWidgets('Personne en ligne pour ce service : état vide et actualiser',
      (tester) async {
    grandEcran(tester);
    await _ouvrir(
        tester,
        h,
        DemandeArgs(CategorieService.nuisibles,
            reprise: DemandeMenage.initiale(CategorieService.nuisibles),
            photosEnvoyees: const ['c1/d/1.jpg']));
    expect(find.text('Personne en ligne pour ce service'), findsOneWidget);
    expect(find.text('Actualiser'), findsOneWidget);
    // Rien à réserver : le bouton le dit, sans message d'erreur.
    expect(find.text('Indisponible'), findsOneWidget);
    expect(_boutonReserver, findsNothing);
    await _fin(tester);
  });

  for (final (size, scale) in const [
    (Size(360, 640), 1.0),
    (Size(360, 640), 1.3),
    (Size(412, 915), 1.0),
  ]) {
    testWidgets(
        'Sans débordement en ${size.width.toInt()}×${size.height.toInt()} '
        '(texte ×$scale), étapes 1, 2 et récapitulatif', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = size * 3;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      for (final c in CategorieService.values) {
        await _ouvrir(tester, h, DemandeArgs(c));
        expect(tester.takeException(), isNull, reason: '${c.code} étape 1');
        await tester.tap(find.text('Abonnement'));
        await tester.pump();
        await tester.tap(find.text('Continuer'));
        await _settle(tester);
        expect(tester.takeException(), isNull, reason: '${c.code} étape 2');
        await tester.pumpWidget(const SizedBox());
      }

      h.prestataires.liste = [_awa, _ben];
      await _ouvrir(
          tester,
          h,
          DemandeArgs(CategorieService.menage,
              reprise: DemandeMenage.initiale(CategorieService.menage),
              photosEnvoyees: const ['c1/d/1.jpg']));
      expect(tester.takeException(), isNull, reason: 'récapitulatif');
      await _fin(tester);
    });
  }
}
