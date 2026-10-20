import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanda/features/auth/citoyen_login_page.dart';

Widget _app() =>
    const ProviderScope(child: MaterialApp(home: LoginCitoyenPage()));

void main() {
  testWidgets('Connexion citoyen : formulaire WhatsApp dans le style ville',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Connexion par WhatsApp'), findsOneWidget);
    expect(find.text('Recevoir le code WhatsApp'), findsOneWidget);
    // Le numéro + code est le seul moyen de connexion.
    expect(find.textContaining('Ancien compte'), findsNothing);
    expect(find.text('Email'), findsNothing);
    expect(find.text('Mot de passe'), findsNothing);
  });

  for (final size in const [Size(360, 640), Size(412, 915)]) {
    testWidgets(
        'Connexion citoyen sans débordement en '
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
