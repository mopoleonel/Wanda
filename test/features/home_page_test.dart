import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanda/features/home/home_page.dart';

Widget _app() => const ProviderScope(child: MaterialApp(home: HomePage()));

void main() {
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
