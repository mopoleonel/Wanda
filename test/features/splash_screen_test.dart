import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wanda/core/api/session.dart';
import 'package:wanda/core/providers/repository_providers.dart';
import 'package:wanda/core/router/app_routes.dart';
import 'package:wanda/features/splash/splash_screen.dart';

Future<Widget> _app({Session? session}) async {
  final gestion = GestionSession(StockageSessionMemoire());
  if (session != null) await gestion.ouvrir(session);
  final router = GoRouter(routes: [
    GoRoute(path: AppRoutes.splash, builder: (_, __) => const SplashScreen()),
    GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => const Scaffold(body: Text('accueil'))),
    GoRoute(
        path: AppRoutes.dashboardParticulier,
        builder: (_, __) => const Scaffold(body: Text('espace prestataire'))),
  ]);
  return ProviderScope(
    overrides: [gestionSessionProvider.overrideWithValue(gestion)],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('Splash : logo, nom et slogan de la marque', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(await _app());
    // Après l'entrée en fondu du logo.
    await tester.pump(const Duration(milliseconds: 1000));

    expect(find.text('WANDA'), findsOneWidget);
    expect(find.text("L'œil intelligent de la ville"), findsOneWidget);
    expect(find.bySemanticsLabel('Logo WANDA'), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 3));
    semantics.dispose();
  });

  testWidgets('Splash : mène à l’accueil après le chargement', (tester) async {
    await tester.pumpWidget(await _app());
    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.text('accueil'), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('accueil'), findsOneWidget);
  });

  testWidgets('Splash : compte resté connecté, ouverture directe de son espace',
      (tester) async {
    await tester.pumpWidget(await _app(
        session: const Session(
            acces: 'a',
            rafraichissement: 'r',
            userId: 'u',
            telephone: '+237690000001',
            typeCompte: 'particulier')));
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(find.text('espace prestataire'), findsOneWidget);
    expect(find.text('accueil'), findsNothing);
  });
}
