import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wanda/core/theme/app_theme.dart';
import 'package:wanda/features/signalement/signal_page.dart';

Widget _app() {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const SignalPage()),
  ]);
  return ProviderScope(
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  );
}

FilledButton _bottomAction(WidgetTester tester) => tester
    .widget<FilledButton>(find.byWidgetPredicate((w) => w is FilledButton));

void main() {
  testWidgets('Étape 1 : « Continuer » reste inactif tant qu’aucun incident',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text("Quel est l'incident ?"), findsOneWidget);
    expect(find.text('Signalement · étape 1 sur 3'), findsOneWidget);
    for (final t in ["Dépôt d'ordures", "Fuite d'eau", 'Électricité']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(_bottomAction(tester).onPressed, isNull);

    await tester.tap(find.text("Fuite d'eau"));
    await tester.pump();
    expect(_bottomAction(tester).onPressed, isNotNull);
  });

  testWidgets('Étape 2 : photo demandée, l’incident peut être changé',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Électricité'));
    await tester.pump();
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();

    expect(find.text('Prenez une photo'), findsOneWidget);
    expect(find.text('Ouvrir la caméra'), findsOneWidget);
    expect(find.text('Touchez pour prendre la photo'), findsOneWidget);
    expect(find.text('Incident : Électricité', findRichText: true),
        findsOneWidget);

    await tester.tap(find.text('Changer'));
    await tester.pumpAndSettle();
    expect(find.text("Quel est l'incident ?"), findsOneWidget);
    // Le choix précédent est conservé.
    expect(_bottomAction(tester).onPressed, isNotNull);
  });

  // Petit Android, et texte agrandi par le système : pas de débordement.
  for (final (size, scale) in const [
    (Size(360, 640), 1.0),
    (Size(360, 640), 1.3),
    (Size(412, 915), 1.0),
  ]) {
    testWidgets(
        'Signalement sans débordement en ${size.width.toInt()}×'
        '${size.height.toInt()} (texte ×$scale)', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = size * 3;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text("Dépôt d'ordures"));
      await tester.pump();
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
