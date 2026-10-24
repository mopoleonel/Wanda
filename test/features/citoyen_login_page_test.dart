import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanda/core/providers/repository_providers.dart';
import 'package:wanda/core/theme/app_theme.dart';
import 'package:wanda/data/repositories/auth_repository.dart';
import 'package:wanda/features/auth/citoyen_login_page.dart';

class _FakeAuth extends Fake implements AuthRepository {
  String? sentTo;
  @override
  Future<void> sendWhatsAppOtp(String phone) async => sentTo = phone;
}

Widget _app({AuthRepository? auth}) => ProviderScope(
      overrides: [
        if (auth != null) authRepositoryProvider.overrideWithValue(auth),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const LoginCitoyenPage()),
    );

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

  testWidgets('La touche « Envoyer » du clavier envoie le code',
      (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(_app(auth: auth));
    await tester.pump(const Duration(seconds: 1));

    await tester.enterText(find.byType(TextFormField), '690000002');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump(const Duration(seconds: 1));

    expect(auth.sentTo, '+237690000002');
    expect(find.text('Entrez le code'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
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
