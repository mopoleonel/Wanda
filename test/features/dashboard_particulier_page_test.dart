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
import 'package:wanda/data/repositories/avis_repository.dart';
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
  @override
  Future<List<Sollicitation>> fetchForPrestataire(String prestataireId,
          {int page = 0, int pageSize = 30}) async =>
      const [];
}

class _FakePrestataires extends Fake implements PrestataireRepository {}

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
      sollicitationRepositoryProvider.overrideWithValue(_FakeSollicitations()),
      prestataireRepositoryProvider.overrideWithValue(_FakePrestataires()),
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
}
