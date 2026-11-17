import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wanda/core/notifications/push_notification_service.dart';
import 'package:wanda/core/providers/repository_providers.dart';
import 'package:wanda/core/router/app_routes.dart';
import 'package:wanda/core/theme/app_theme.dart';
import 'package:wanda/data/models/particulier.dart';
import 'package:wanda/data/repositories/auth_repository.dart';
import 'package:wanda/data/repositories/profile_repository.dart';
import 'package:wanda/features/auth/presta_login_page.dart';

class _FakeAuth extends Fake implements AuthRepository {
  _FakeAuth({this.userType});

  /// Type du compte déjà associé au numéro (null : nouveau numéro).
  UserType? userType;
  String? sentTo;
  bool signedOut = false;

  @override
  String? get currentUserId => signedOut ? null : 'u1';

  @override
  Future<void> sendWhatsAppOtp(String phone) async => sentTo = phone;

  @override
  Future<String> verifyWhatsAppOtp(
          {required String phone,
          required String code,
          String? typeCompte}) async =>
      'u1';

  @override
  Future<UserType?> fetchUserType(String userId) async => userType;

  @override
  Future<void> signOut() async => signedOut = true;
}

class _FakeProfiles extends Fake implements ProfileRepository {
  _FakeProfiles(this.auth);

  final _FakeAuth auth;
  final created = <String, String>{};

  @override
  Future<void> createProfileEntry(String userId, String userType) async {
    auth.userType = userTypeFromString(userType);
  }

  @override
  Future<void> createParticulier({
    required String id,
    required String telephone,
    String nom = '',
    String prenom = '',
    List<String> services = const [],
    String? photoProUrl,
  }) async =>
      created[id] = telephone;

  @override
  Future<Particulier?> fetchParticulier(String id) async {
    final phone = created[id];
    return phone == null
        ? null
        : Particulier(id: id, nom: '', prenom: '', telephone: phone);
  }
}

class _FakePush extends Fake implements PushNotificationService {
  @override
  Future<void> registerDeviceForUser(String userId) async {}
}

Widget _app({_FakeAuth? auth, _FakeProfiles? profiles}) {
  final a = auth ?? _FakeAuth();
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const LoginPrestaPage()),
    GoRoute(
        path: AppRoutes.dashboardParticulier,
        builder: (_, __) => const Text('ESPACE PRESTATAIRE')),
  ]);
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(a),
      profileRepositoryProvider.overrideWithValue(profiles ?? _FakeProfiles(a)),
      pushNotificationServiceProvider.overrideWithValue(_FakePush()),
    ],
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  );
}

/// Laisse passer appels asynchrones et transitions ; pas de pumpAndSettle,
/// l'en-tête (ville, scène) et le compte à rebours s'animent en continu.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<void> _receiveCode(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField), '699 00 00 01');
  await tester.tap(find.text('Recevoir le code WhatsApp'));
  await _settle(tester);
}

Future<void> _typeCode(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField), '123456');
  await _settle(tester);
}

void main() {
  testWidgets('Premier écran : numéro seul, ni mot de passe ni services',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Numéro de téléphone'), findsOneWidget);
    expect(find.text('Recevoir le code WhatsApp'), findsOneWidget);
    expect(find.text('Mot de passe'), findsNothing);
    expect(find.text('Vos services'), findsNothing);
    expect(find.text('Email'), findsNothing);
  });

  testWidgets('Numéro invalide refusé', (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(_app(auth: auth));
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.byType(TextFormField), '12');
    await tester.tap(find.text('Recevoir le code WhatsApp'));
    await tester.pump();
    expect(find.text('Numéro invalide'), findsOneWidget);
    expect(auth.sentTo, isNull);

    // Une fois corrigé, l'erreur disparaît sans nouvel envoi.
    await tester.enterText(find.byType(TextFormField), '699 00 00 01');
    await tester.pump();
    expect(find.text('Numéro invalide'), findsNothing);
    expect(auth.sentTo, isNull);
  });

  testWidgets(
      'Inscription : numéro → code → « Indépendant » → son espace, '
      'compte créé avec le numéro seul', (tester) async {
    final auth = _FakeAuth();
    final profiles = _FakeProfiles(auth);
    await tester.pumpWidget(_app(auth: auth, profiles: profiles));
    await tester.pump(const Duration(seconds: 1));

    await _receiveCode(tester);
    expect(auth.sentTo, '+237699000001');
    expect(find.text('Entrez le code'), findsOneWidget);

    await _typeCode(tester);
    expect(find.text('Créer votre compte'), findsOneWidget);
    expect(find.text('Indépendant'), findsOneWidget);
    expect(find.text('Vos services'), findsNothing);

    await tester.tap(find.text('Créer mon compte'));
    await _settle(tester);
    expect(profiles.created, {'u1': '+237699000001'});
    expect(find.text('ESPACE PRESTATAIRE'), findsOneWidget);
  });

  testWidgets('Compte existant : le code mène directement à son espace',
      (tester) async {
    final auth = _FakeAuth(userType: UserType.particulier);
    final profiles = _FakeProfiles(auth)..created['u1'] = '+237699000001';
    await tester.pumpWidget(_app(auth: auth, profiles: profiles));
    await tester.pump(const Duration(seconds: 1));

    await _receiveCode(tester);
    await _typeCode(tester);
    expect(find.text('Créer votre compte'), findsNothing);
    expect(find.text('ESPACE PRESTATAIRE'), findsOneWidget);
  });

  testWidgets('Numéro d\'un compte citoyen refusé', (tester) async {
    final auth = _FakeAuth(userType: UserType.citoyen);
    await tester.pumpWidget(_app(auth: auth));
    await tester.pump(const Duration(seconds: 1));

    await _receiveCode(tester);
    await _typeCode(tester);
    expect(auth.signedOut, isTrue);
    expect(find.textContaining('compte citoyen'), findsOneWidget);
  });

  testWidgets('Plus d\'option « ancien compte » ni de mot de passe',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Ancien compte'), findsNothing);
    expect(find.textContaining('mot de passe'), findsNothing);
  });

  for (final size in const [Size(360, 640), Size(412, 915)]) {
    final label = '${size.width.toInt()}×${size.height.toInt()}';

    testWidgets('Écran prestataire sans débordement en $label', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = size * 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app());
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Espace prestataire'), findsWidgets);
      expect(tester.takeException(), isNull);

      await _receiveCode(tester);
      await _typeCode(tester);
      expect(find.text('Créer votre compte'), findsOneWidget);
      // Choix « Entreprise » : le formulaire le plus long.
      await tester.tap(find.text('Entreprise'));
      await _settle(tester);
      expect(find.text("Nom de l'entreprise"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
