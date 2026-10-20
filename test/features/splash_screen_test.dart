import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wanda/core/router/app_routes.dart';
import 'package:wanda/features/splash/splash_screen.dart';

Widget _app() {
  final router = GoRouter(routes: [
    GoRoute(path: AppRoutes.splash, builder: (_, __) => const SplashScreen()),
    GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => const Scaffold(body: Text('accueil'))),
  ]);
  return MaterialApp.router(routerConfig: router);
}

void main() {
  testWidgets('Splash : logo, nom et slogan de la marque', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app());
    // Après l'entrée en fondu du logo.
    await tester.pump(const Duration(milliseconds: 1000));

    expect(find.text('WANDA'), findsOneWidget);
    expect(find.text("L'œil intelligent de la ville"), findsOneWidget);
    expect(find.bySemanticsLabel('Logo WANDA'), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 3));
    semantics.dispose();
  });

  testWidgets('Splash : mène à l’accueil après le chargement', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.text('accueil'), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('accueil'), findsOneWidget);
  });
}
