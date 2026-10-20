import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanda/features/certification/certification_page.dart';

Widget _app() =>
    const ProviderScope(child: MaterialApp(home: CertificationPage()));

void main() {
  testWidgets('Certification : facultative, met en avant le badge',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Certifier mon compte'), findsOneWidget);
    expect(find.text('Badge « Identité vérifiée »'), findsOneWidget);
    expect(find.textContaining('Facultatif'), findsOneWidget);
  });

  testWidgets('Étape recto : photo obligatoire avant de continuer',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Commencer'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Étape 1 sur 4'), findsOneWidget);
    expect(find.text('Photographier la carte'), findsOneWidget);
    expect(find.text('Continuer'), findsNothing);
  });

  for (final size in const [Size(360, 640), Size(412, 915)]) {
    testWidgets(
        'Certification sans débordement en '
        '${size.width.toInt()}×${size.height.toInt()}', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = size * 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  }
}
