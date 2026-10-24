import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wanda/core/providers/repository_providers.dart';
import 'package:wanda/core/router/app_routes.dart';
import 'package:wanda/data/repositories/auth_repository.dart';
import 'package:wanda/features/home/home_page.dart';

Widget _app() => const ProviderScope(child: MaterialApp(home: HomePage()));

void main() {
  mainNavigation();

  testWidgets('HomePage affiche le slogan et les deux rôles disponibles',
      (WidgetTester tester) async {
    await tester.pumpWidget(_app());

    expect(find.text("L'œil intelligent\nde la ville"), findsOneWidget);
    expect(find.text('Citoyen'), findsOneWidget);
    expect(find.text('Prestataire'), findsOneWidget);
  });

  // L'accueil doit tenir sur un seul écran, sans débordement, du petit
  // Android (360 × 640) au grand téléphone (412 × 915).
  for (final size in const [Size(360, 640), Size(412, 915)]) {
    testWidgets(
        'HomePage tient sans débordement en ${size.width.toInt()}×'
        '${size.height.toInt()}', (WidgetTester tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = size * 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app());
      await tester.pump(const Duration(seconds: 2));

      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsNothing);
    });
  }
}

class _FakeAuth extends Fake implements AuthRepository {
  _FakeAuth(this.uid, this.type);
  final String? uid;
  final UserType? type;
  @override
  String? get currentUserId => uid;
  @override
  Future<UserType?> fetchUserType(String userId) async => type;
}

Widget _appRoutee(_FakeAuth auth) {
  Widget ecran(String nom) => Scaffold(body: Text(nom));
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const HomePage()),
    GoRoute(
        path: AppRoutes.citoyenLogin,
        builder: (_, __) => ecran('CONNEXION CITOYEN')),
    GoRoute(
        path: AppRoutes.citoyenServices,
        builder: (_, __) => ecran('ESPACE CITOYEN')),
    GoRoute(
        path: AppRoutes.prestaLogin,
        builder: (_, __) => ecran('CONNEXION PRESTATAIRE')),
    GoRoute(
        path: AppRoutes.dashboardParticulier,
        builder: (_, __) => ecran('ESPACE PRESTATAIRE')),
    GoRoute(
        path: AppRoutes.dashboardEntreprise,
        builder: (_, __) => ecran('ESPACE ENTREPRISE')),
  ]);
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(auth)],
    child: MaterialApp.router(routerConfig: router),
  );
}

void mainNavigation() {
  for (final (session, carte, attendu) in [
    (_FakeAuth(null, null), 'Citoyen', 'CONNEXION CITOYEN'),
    (_FakeAuth('c1', UserType.citoyen), 'Citoyen', 'ESPACE CITOYEN'),
    // Prestataire connecté qui touche « Citoyen » : pas dans l'espace d'un
    // autre rôle, il passe par la connexion citoyen.
    (_FakeAuth('p1', UserType.particulier), 'Citoyen', 'CONNEXION CITOYEN'),
    (
      _FakeAuth('p1', UserType.particulier),
      'Prestataire',
      'ESPACE PRESTATAIRE'
    ),
    (_FakeAuth('e1', UserType.entreprise), 'Prestataire', 'ESPACE ENTREPRISE'),
    (_FakeAuth('c1', UserType.citoyen), 'Prestataire', 'CONNEXION PRESTATAIRE'),
  ]) {
    testWidgets(
        'Session ${session.type?.name ?? 'absente'} + « $carte » → $attendu',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 1600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_appRoutee(session));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text(carte));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text(attendu), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
  }
}
