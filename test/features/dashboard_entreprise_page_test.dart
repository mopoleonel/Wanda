import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wanda/core/error/app_exception.dart';
import 'package:wanda/core/providers/repository_providers.dart';
import 'package:wanda/core/theme/app_theme.dart';
import 'package:wanda/data/models/entreprise.dart';
import 'package:wanda/data/models/secteur.dart';
import 'package:wanda/data/models/signalement.dart';
import 'package:wanda/data/repositories/auth_repository.dart';
import 'package:wanda/data/repositories/profile_repository.dart';
import 'package:wanda/data/repositories/signalement_repository.dart';
import 'package:wanda/features/dashboard_entreprise/dashboard_entreprise_page.dart';

class _FakeAuth extends Fake implements AuthRepository {
  @override
  String? get currentUserId => 'e1';
}

class _FakeProfiles extends Fake implements ProfileRepository {
  String? savedPhone;

  @override
  Future<Entreprise?> fetchEntreprise(String id) async => const Entreprise(
      id: 'e1',
      nomEntreprise: 'CDE Douala',
      secteurActivite: secteurHydraulique,
      telephone: '+237699000009');

  @override
  Future<void> updateEntreprise({
    required String id,
    required String nomEntreprise,
    required String telephone,
  }) async =>
      savedPhone = telephone;
}

class _FakeSignalements extends Fake implements SignalementRepository {
  _FakeSignalements(this.rows, {this.fail = false});
  List<Signalement> rows;
  bool fail;
  String? askedEntreprise;
  List<String>? askedTypes;
  final updates = <String, String>{};

  @override
  Future<List<Signalement>> fetchForEntreprise(
      String entrepriseId, List<String> types,
      {int pageSize = 100}) async {
    askedEntreprise = entrepriseId;
    askedTypes = types;
    if (fail) throw const AppException('Erreur réseau.');
    return rows;
  }

  @override
  Future<void> updateStatut(String id, String statut) async {
    updates[id] = statut;
    rows = [
      for (final r in rows)
        r.id == id
            ? Signalement(
                id: r.id,
                typeProbleme: r.typeProbleme,
                imageUrl: '',
                latitude: 0,
                longitude: 0,
                statut: statut)
            : r
    ];
  }
}

Signalement _sig(String id, String statut, [String type = "Fuite d'eau"]) =>
    Signalement(
        id: id,
        typeProbleme: type,
        imageUrl: '',
        latitude: 4.05,
        longitude: 9.7,
        statut: statut);

Widget _app(_FakeSignalements sigs, [_FakeProfiles? profiles]) {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const DashboardEntreprisePage()),
  ]);
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuth()),
      profileRepositoryProvider.overrideWithValue(profiles ?? _FakeProfiles()),
      signalementRepositoryProvider.overrideWithValue(sigs),
    ],
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  void tallScreen(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 2000);
    addTearDown(tester.view.reset);
  }

  testWidgets('Missions de l\'entreprise ET des types de son secteur',
      (tester) async {
    tallScreen(tester);
    final sigs = _FakeSignalements([
      _sig('101', 'en_attente'),
      _sig('102', 'en_cours', 'Canalisation bouchée'),
      _sig('103', 'resolu'),
      _sig('104', 'rejete'),
    ]);
    await tester.pumpWidget(_app(sigs));
    await _settle(tester);

    expect(sigs.askedEntreprise, 'e1');
    expect(sigs.askedTypes, ["Fuite d'eau"]);
    expect(find.text('CDE Douala'), findsOneWidget);
    // Actives : reçue et en cours ; ni résolue ni rejetée.
    expect(find.text('N° 000101'), findsOneWidget);
    expect(find.text('N° 000102'), findsOneWidget);
    expect(find.text('N° 000103'), findsNothing);
    expect(find.text('N° 000104'), findsNothing);
  });

  testWidgets('Historique : résolues et rejetées', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(_app(_FakeSignalements([
      _sig('101', 'en_attente'),
      _sig('103', 'resolu'),
      _sig('104', 'rejete'),
    ])));
    await _settle(tester);
    await tester.tap(find.text('Historique'));
    await _settle(tester);

    expect(find.text('N° 000103'), findsOneWidget);
    expect(find.text('N° 000104'), findsOneWidget);
    expect(find.text('N° 000101'), findsNothing);
    expect(find.textContaining('2 signalements traités'), findsOneWidget);
  });

  testWidgets('Prendre en charge une mission reçue', (tester) async {
    tallScreen(tester);
    final sigs = _FakeSignalements([_sig('101', 'en_attente')]);
    await tester.pumpWidget(_app(sigs));
    await _settle(tester);

    await tester.tap(find.text('N° 000101'));
    await _settle(tester);
    await tester.tap(find.text('Prendre en charge'));
    await _settle(tester);

    expect(sigs.updates, {'101': 'en_cours'});
    expect(find.text('Mission prise en charge.'), findsOneWidget);
  });

  testWidgets('Rejeter demande confirmation puis classe le signalement',
      (tester) async {
    tallScreen(tester);
    final sigs = _FakeSignalements([_sig('101', 'en_attente')]);
    await tester.pumpWidget(_app(sigs));
    await _settle(tester);

    await tester.tap(find.text('N° 000101'));
    await _settle(tester);
    await tester.tap(find.text('Rejeter le signalement'));
    await _settle(tester);
    expect(find.text('Rejeter ce signalement ?'), findsOneWidget);

    await tester.tap(find.text('Annuler'));
    await _settle(tester);
    expect(sigs.updates, isEmpty);

    await tester.tap(find.text('Rejeter le signalement'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Rejeter'));
    await _settle(tester);
    expect(sigs.updates, {'101': 'rejete'});
  });

  testWidgets('Erreur de chargement : message et « Réessayer », pas de vide',
      (tester) async {
    tallScreen(tester);
    final sigs = _FakeSignalements(const [], fail: true);
    await tester.pumpWidget(_app(sigs));
    await _settle(tester);

    expect(find.text('Impossible de charger vos missions.'), findsOneWidget);
    expect(find.text('Aucune mission active'), findsNothing);

    sigs
      ..fail = false
      ..rows = [_sig('101', 'en_attente')];
    await tester.tap(find.text('Réessayer'));
    await _settle(tester);
    expect(find.text('N° 000101'), findsOneWidget);
  });

  testWidgets('Profil : téléphone verrouillé, conservé à l\'enregistrement',
      (tester) async {
    tallScreen(tester);
    final profiles = _FakeProfiles();
    await tester.pumpWidget(_app(_FakeSignalements(const []), profiles));
    await _settle(tester);
    await tester.tap(find.text('Profil'));
    await _settle(tester);

    final phone = tester.widget<TextField>(find.ancestor(
        of: find.text('Téléphone (identifiant de connexion)'),
        matching: find.byType(TextField)));
    expect(phone.enabled, isFalse);

    await tester.tap(find.text('Enregistrer'));
    await _settle(tester);
    expect(profiles.savedPhone, '+237699000009');
  });

  for (final size in const [Size(360, 640), Size(412, 915)]) {
    testWidgets(
        'Tableau de bord entreprise sans débordement en '
        '${size.width.toInt()}×${size.height.toInt()}', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = size * 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(_FakeSignalements([
        _sig('101', 'en_attente',
            'Canalisation principale éclatée devant le marché central'),
        _sig('102', 'en_cours'),
      ])));
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
