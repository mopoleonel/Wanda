import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wanda/core/providers/repository_providers.dart';
import 'package:wanda/core/router/app_routes.dart';
import 'package:wanda/core/theme/app_theme.dart';
import 'package:wanda/data/models/avis_prestataire.dart';
import 'package:wanda/data/models/particulier.dart';
import 'package:wanda/data/models/sollicitation.dart';
import 'package:wanda/data/models/verification_identite.dart';
import 'package:wanda/data/repositories/auth_repository.dart';
import 'package:wanda/data/models/ajustement.dart';
import 'package:wanda/data/repositories/avis_repository.dart';
import 'package:wanda/data/pricing/tarification.dart';
import 'package:wanda/data/repositories/demande_repository.dart';
import 'package:wanda/data/repositories/prestataire_repository.dart';
import 'package:wanda/data/repositories/profile_repository.dart';
import 'package:wanda/data/repositories/sollicitation_repository.dart';
import 'package:wanda/data/repositories/verification_repository.dart';
import 'package:wanda/features/dashboard_particulier/dashboard_particulier_page.dart';

class _FakeAuth extends Fake implements AuthRepository {
  @override
  String? get currentUserId => 'u1';
}

class _FakeProfiles extends Fake implements ProfileRepository {
  _FakeProfiles(this.particulier);
  Particulier particulier;
  int updates = 0;
  List<String>? savedServices;

  @override
  Future<Particulier?> fetchParticulier(String id) async => particulier;

  @override
  Future<void> updateParticulierInfo({
    required String id,
    required String nom,
    required String telephone,
    String? prenom,
    List<String>? services,
  }) async {
    updates++;
    savedServices = services;
  }
}

class _FakeAvis extends Fake implements AvisRepository {
  @override
  Future<RatingSummary> averageForPrestataire(String prestataireId) async =>
      RatingSummary.empty;
}

class _FakeVerifications extends Fake implements VerificationRepository {
  _FakeVerifications(this.latest);
  final VerificationIdentite? latest;

  @override
  Future<VerificationIdentite?> latestFor(String userId) async => latest;
}

class _FakeSollicitations extends Fake implements SollicitationRepository {
  List<Sollicitation> missions = const [];
  @override
  Future<List<Sollicitation>> fetchForPrestataire(String prestataireId,
          {int page = 0, int pageSize = 30}) async =>
      missions;
}

class _FakePrestataires extends Fake implements PrestataireRepository {}

class _FakeDemandes extends Fake implements DemandeRepository {
  final refus = <String, String?>{};
  final ajustementsEnvoyes = <Map<String, Object>>[];

  @override
  Future<List<Ajustement>> ajustements(List<String> ids) async => const [];

  @override
  Future<void> refuser(String id, {String? motif}) async => refus[id] = motif;

  @override
  Future<void> demanderAjustement({
    required String sollicitationId,
    required int minutes,
    required int produits,
    required String motif,
    List<String> photos = const [],
  }) async =>
      ajustementsEnvoyes.add({
        'id': sollicitationId,
        'minutes': minutes,
        'produits': produits,
        'motif': motif,
      });
}

class _FakeTarifs extends Fake implements TarifRepository {
  @override
  Future<Tarifs> charger() async => Tarifs.defaut;
}

Particulier _artisan({
  String nom = 'Kamga',
  String prenom = 'Paul',
  List<String> services = const ['menage'],
  String? photo = 'https://x/p.jpg',
  bool certifie = false,
}) =>
    Particulier(
      id: 'u1',
      nom: nom,
      prenom: prenom,
      telephone: '+237699000001',
      services: services,
      photoProUrl: photo,
      identiteVerifiee: certifie,
      abonnementExpireAt: DateTime.now().add(const Duration(days: 10)),
      typeAbonnement: 'ESSAI',
      essaiUtilise: true,
    );

const _enAttente =
    VerificationIdentite(id: 'v1', statut: VerificationStatut.enAttente);

final _sollicitations = _FakeSollicitations();
var _demandes = _FakeDemandes();

Widget _app(_FakeProfiles profiles, {VerificationIdentite? verification}) {
  final router = GoRouter(
    initialLocation: AppRoutes.dashboardParticulier,
    routes: [
      GoRoute(
          path: AppRoutes.dashboardParticulier,
          builder: (_, __) => const DashboardParticulierPage()),
      GoRoute(
          path: AppRoutes.identityVerification,
          builder: (_, __) => const Scaffold(body: Text('certification'))),
    ],
  );
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuth()),
      profileRepositoryProvider.overrideWithValue(profiles),
      avisRepositoryProvider.overrideWithValue(_FakeAvis()),
      verificationRepositoryProvider
          .overrideWithValue(_FakeVerifications(verification)),
      sollicitationRepositoryProvider.overrideWithValue(_sollicitations),
      prestataireRepositoryProvider.overrideWithValue(_FakePrestataires()),
      demandeRepositoryProvider.overrideWithValue(_demandes),
      tarifRepositoryProvider.overrideWithValue(_FakeTarifs()),
    ],
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  );
}

/// Laisse le chargement se faire sans attendre les animations infinies.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openProfile(WidgetTester tester) async {
  await tester.tap(find.text('Profil'));
  await _settle(tester);
}

void main() {
  // Grand écran : tout l'onglet Profil tient sans défilement.
  void tallScreen(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 2400);
    addTearDown(tester.view.reset);
  }

  testWidgets('Arrivée, profil incomplet : rappel « compléter puis certifier »',
      (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(_app(
        _FakeProfiles(_artisan(nom: '', services: const [], photo: null))));
    await _settle(tester);

    expect(find.text('Complétez votre profil, puis certifiez votre compte'),
        findsOneWidget);
    await tester.tap(find.text('Compléter mon profil'));
    await _settle(tester);

    expect(find.text('Ma fiche prestataire'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Arrivée, profil complet non certifié : rappel de certification',
      (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(_app(_FakeProfiles(_artisan())));
    await _settle(tester);

    expect(find.text('Faites certifier votre compte'), findsOneWidget);
    expect(
        find.textContaining('ne pourront plus être modifiés'), findsOneWidget);

    await tester.tap(find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Certifier mon compte')));
    await _settle(tester);
    expect(find.text('certification'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('« Plus tard » ferme le rappel, qui ne revient pas aussitôt',
      (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(_app(_FakeProfiles(_artisan())));
    await _settle(tester);

    await tester.tap(find.text('Plus tard'));
    await _settle(tester);
    expect(find.text('Faites certifier votre compte'), findsNothing);

    // Changer d'onglet recharge les données sans rouvrir le rappel.
    await _openProfile(tester);
    await tester.tap(find.text('Mon activité'));
    await _settle(tester);
    expect(find.text('Faites certifier votre compte'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Compte certifié : pas de rappel, identité figée, services '
      'complétables seulement', (tester) async {
    tallScreen(tester);
    final profiles = _FakeProfiles(_artisan(certifie: true));
    await tester.pumpWidget(_app(profiles));
    await _settle(tester);

    expect(find.text('Faites certifier votre compte'), findsNothing);

    await _openProfile(tester);
    expect(
        find.textContaining('Compte certifié : nom, prénom'), findsOneWidget);

    final fields = tester.widgetList<TextField>(find.byType(TextField)).where(
        (f) => const ['Nom', 'Prénom'].contains(f.decoration?.labelText));
    expect(fields, hasLength(2));
    expect(fields.every((f) => f.readOnly && f.enabled == false), isTrue);

    // Le service certifié reste coché (cadenas) et ne peut pas être retiré.
    await tester.tap(find.text('Ménage').last);
    await tester.pump();
    expect(
        find.text('Compte certifié : vous pouvez ajouter des services, '
            'pas en retirer.'),
        findsOneWidget);

    // Un nouveau service peut être ajouté et enregistré.
    await tester.tap(find.text('Linge'));
    await tester.pump();
    await tester.tap(find.text('Enregistrer'));
    await _settle(tester);
    expect(profiles.updates, 1);
    expect(profiles.savedServices, ['menage', 'linge']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Certification en cours : déjà figé, pas de rappel',
      (tester) async {
    tallScreen(tester);
    await tester
        .pumpWidget(_app(_FakeProfiles(_artisan()), verification: _enAttente));
    await _settle(tester);

    expect(find.text('Faites certifier votre compte'), findsNothing);
    await _openProfile(tester);
    final nom = tester
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere((f) => f.decoration?.labelText == 'Nom');
    expect(nom.enabled, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Non certifié : profil modifiable et enregistrable',
      (tester) async {
    tallScreen(tester);
    final profiles = _FakeProfiles(_artisan());
    await tester.pumpWidget(_app(profiles));
    await _settle(tester);
    await tester.tap(find.text('Plus tard'));
    await _settle(tester);

    await _openProfile(tester);
    // Plusieurs services : on coche Nuisibles, on décoche Ménage.
    await tester.tap(find.text('Nuisibles'));
    await tester.tap(find.text('Ménage').last);
    await tester.tap(find.text('Enregistrer'));
    await _settle(tester);
    expect(profiles.updates, 1);
    expect(profiles.savedServices, ['nuisibles']);
    await tester.pumpWidget(const SizedBox());
  });

  group('Missions de services ménagers', () {
    final enAttente = Sollicitation.fromMap({
      'id': '512',
      'prestataire_id': 'u1',
      'citoyen_id': 'c1',
      'nom_citoyen': 'Mbarga',
      'prenom_citoyen': 'Lucie',
      'numero_citoyen': '+237677000000',
      'statut': 'en_attente',
      'date_sollicitation': DateTime.now().toIso8601String(),
      'service': 'menage',
      'formule': 'ponctuelle',
      'reponses': {
        'chambres': 2, 'salons': 1, 'cuisines': 1, 'douche_wc': 1, //
        'vitres': true, 'etat': 'sale',
      },
      'minutes_estimees': 263,
      'prix_passage': 6300,
      'prix_total': 6300,
      'ia_analyse': {
        'photos_conformes': true,
        'estimation': {'niveau': 'tres_sale'},
        'confiance': 0.8,
        'incoherences': ['Le salon paraît très sale'],
      },
      'date_souhaitee': '2026-10-22',
      'creneau': 'matin',
    });
    final confirmee = Sollicitation.fromMap({
      ...{
        'id': '513',
        'prestataire_id': 'u1',
        'citoyen_id': 'c1',
        'nom_citoyen': 'Mbarga',
        'numero_citoyen': '+237677000000',
        'statut': 'accepte',
        'service': 'linge',
        'formule': 'abonnement',
        'frequence': 'hebdomadaire',
        'reponses': {'paniers': 2},
        'prix_passage': 4000,
        'prix_total': 16000,
      },
    });

    setUp(() {
      _demandes = _FakeDemandes();
      _sollicitations.missions = [enAttente, confirmee];
    });
    tearDown(() => _sollicitations.missions = const []);

    Future<void> ouvrirMissions(WidgetTester tester) async {
      tallScreen(tester);
      await tester.pumpWidget(_app(_FakeProfiles(_artisan(certifie: true))));
      await _settle(tester);
      await tester.tap(find.text('Missions'));
      await _settle(tester);
    }

    testWidgets('La demande se lit avant de répondre : réponses, IA, prix',
        (tester) async {
      await ouvrirMissions(tester);
      expect(find.text('Voir la demande et répondre'), findsOneWidget);
      expect(find.text(fcfa(6300)), findsOneWidget);

      await tester.tap(find.text('Voir la demande et répondre'));
      await _settle(tester);
      expect(find.text('2 chambres, 1 salon, 1 cuisine, 1 douche / WC'),
          findsOneWidget);
      expect(find.text('En plus : vitres'), findsOneWidget);
      expect(find.text('Estimation IA : tres sale'), findsOneWidget);
      expect(find.text('• Le salon paraît très sale'), findsOneWidget);
      expect(find.text('Accepter (${fcfa(6300)}) et appeler'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Refuser : motif facultatif transmis', (tester) async {
      await ouvrirMissions(tester);
      await tester.tap(find.text('Voir la demande et répondre'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Refuser'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).last, 'Pas dispo jeudi');
      await tester.tap(find.widgetWithText(FilledButton, 'Refuser'));
      await _settle(tester);
      expect(_demandes.refus, {'512': 'Pas dispo jeudi'});
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Mission confirmée : ajustement chiffré puis envoyé',
        (tester) async {
      await ouvrirMissions(tester);
      await tester.tap(find.text('En cours (1)'));
      await _settle(tester);
      expect(find.text('Pointer'), findsOneWidget,
          reason: 'abonnement : pointage des passages');
      await tester.tap(find.text('Ajustement'));
      await _settle(tester);

      // 30 min par défaut = 600 FCFA ; +15 min = 45 min = 900 FCFA.
      expect(find.text('Envoyer au client : +${fcfa(600)}'), findsOneWidget);
      await tester.tap(find.byTooltip('Plus').first);
      await tester.pump();
      expect(find.text('Envoyer au client : +${fcfa(900)}'), findsOneWidget);

      // Motif obligatoire.
      await tester.tap(find.text('Envoyer au client : +${fcfa(900)}'));
      await _settle(tester);
      expect(_demandes.ajustementsEnvoyes, isEmpty);

      await tester.enterText(
          find.widgetWithText(TextField, 'Pourquoi ?'), 'Deux paniers de plus');
      await tester.tap(find.text('Envoyer au client : +${fcfa(900)}'));
      await _settle(tester);
      expect(_demandes.ajustementsEnvoyes.single, {
        'id': '513',
        'minutes': 45,
        'produits': 0,
        'motif': 'Deux paniers de plus',
      });
      await tester.pumpWidget(const SizedBox());
    });
  });
}
