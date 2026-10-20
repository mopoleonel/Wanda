import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wanda/core/providers/repository_providers.dart';
import 'package:wanda/core/theme/app_theme.dart';
import 'package:wanda/data/models/avis_prestataire.dart';
import 'package:wanda/data/models/citoyen.dart';
import 'package:wanda/data/models/particulier.dart';
import 'package:wanda/data/models/sollicitation.dart';
import 'package:wanda/data/repositories/auth_repository.dart';
import 'package:wanda/data/repositories/avis_repository.dart';
import 'package:wanda/data/repositories/prestataire_repository.dart';
import 'package:wanda/data/repositories/profile_repository.dart';
import 'package:wanda/data/repositories/sollicitation_repository.dart';
import 'package:wanda/features/services/service_page.dart';

class _FakeAuth extends Fake implements AuthRepository {
  @override
  String? get currentUserId => 'c1';
  @override
  bool get hasVerifiedPhone => true;
}

class _FakeProfiles extends Fake implements ProfileRepository {
  _FakeProfiles(this.citoyen);
  final Citoyen? citoyen;
  @override
  Future<Citoyen?> fetchCitoyen(String id) async => citoyen;
}

class _FakeAvis extends Fake implements AvisRepository {
  @override
  Future<Map<String, RatingSummary>> averagesForPrestataires(
          List<String> ids) async =>
      {'p1': const RatingSummary(average: 4.5, count: 4)};
}

/// Flux temps réel pilotés par le test ; compte les abonnements.
class _FakePrestataires extends Fake implements PrestataireRepository {
  final controller = StreamController<List<Particulier>>.broadcast();
  int listens = 0;

  @override
  Stream<List<Particulier>> streamAvailable() {
    listens++;
    return controller.stream;
  }
}

class _FakeSollicitations extends Fake implements SollicitationRepository {
  final controller = StreamController<List<Sollicitation>>.broadcast();
  int listens = 0;
  final created = <String>[];

  @override
  Stream<List<Sollicitation>> streamForCitoyen(String citoyenId) {
    listens++;
    return controller.stream;
  }

  @override
  Future<void> create({
    required String prestataireId,
    required String citoyenId,
    required String nomCitoyen,
    String? prenomCitoyen,
    required String numeroCitoyen,
  }) async =>
      created.add(prestataireId);
}

const _paul = Particulier(
    id: 'p1',
    nom: 'Kamga',
    prenom: 'Paul',
    telephone: '+237699000001',
    services: ['menage'],
    isAvailable: true);
const _awa = Particulier(
    id: 'p2',
    nom: 'Ngo',
    prenom: 'Awa',
    telephone: '+237699000002',
    services: ['linge', 'dechets'],
    isAvailable: true);

const _citoyen = Citoyen(
    citoyenId: 'c1',
    nom: 'Mbarga',
    prenom: 'Lucie',
    email: '',
    telephone: '+237677000000');

class _Harness {
  final prestataires = _FakePrestataires();
  final sollicitations = _FakeSollicitations();

  Widget app({Citoyen? citoyen = _citoyen}) {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const ServicePage()),
    ]);
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuth()),
        profileRepositoryProvider.overrideWithValue(_FakeProfiles(citoyen)),
        avisRepositoryProvider.overrideWithValue(_FakeAvis()),
        prestataireRepositoryProvider.overrideWithValue(prestataires),
        sollicitationRepositoryProvider.overrideWithValue(sollicitations),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late _Harness h;
  setUp(() => h = _Harness());

  void tallScreen(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 2000);
    addTearDown(tester.view.reset);
  }

  testWidgets('Chargement puis prestataires en ligne, avec la salutation',
      (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(h.app());
    await _settle(tester);
    expect(find.text('Recherche des prestataires en ligne…'), findsOneWidget);

    h.prestataires.controller.add([_paul, _awa]);
    await _settle(tester);

    expect(find.text('Bonjour, Lucie'), findsOneWidget);
    expect(find.text('2 prestataires disponibles maintenant'), findsOneWidget);
    expect(find.text('Paul Kamga'), findsWidgets);
    expect(find.text('Awa Ngo'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Filtre par service, et état vide avec retour à « Tous »',
      (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(h.app());
    h.prestataires.controller.add([_paul, _awa]);
    await _settle(tester);

    // Awa propose Linge et Déchets : visible sous Déchets.
    await tester.ensureVisible(find.text('Déchets').first);
    await _settle(tester);
    await tester.tap(find.text('Déchets').first);
    await _settle(tester);
    expect(find.text('Awa Ngo'), findsWidgets);
    expect(find.text('Paul Kamga'), findsNothing);

    await tester.ensureVisible(find.text('Nuisibles').first);
    await _settle(tester);
    await tester.tap(find.text('Nuisibles').first);
    await _settle(tester);
    expect(find.text('Personne en ligne pour ce service'), findsOneWidget);

    await tester.tap(find.text('Voir tous les services'));
    await _settle(tester);
    expect(find.text('Paul Kamga'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Un seul abonnement temps réel malgré les reconstructions',
      (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(h.app());
    h.prestataires.controller.add([_paul, _awa]);
    await _settle(tester);

    // Changer de service, d'onglet, puis revenir : aucun réabonnement.
    await tester.tap(find.text('Ménage').first);
    await _settle(tester);
    await tester.tap(find.text('Mes demandes'));
    await _settle(tester);
    await tester.tap(find.text('Services'));
    await _settle(tester);

    expect(h.prestataires.listens, 1);
    expect(h.sollicitations.listens, 1);
    // Les prestataires restent affichés sans repasser par le chargement.
    expect(find.text('Recherche des prestataires en ligne…'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Solliciter un expert crée la demande et ouvre le suivi',
      (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(h.app());
    h.prestataires.controller.add([_paul]);
    await _settle(tester);

    await tester.tap(find.text('Paul Kamga').last);
    await _settle(tester);
    await tester.tap(find.text('Solliciter Paul'));
    await _settle(tester);

    expect(h.sollicitations.created, ['p1']);
    expect(find.text('Mes demandes'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Profil incomplet : la sollicitation renvoie vers le profil',
      (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(h.app(citoyen: null));
    h.prestataires.controller.add([_paul]);
    await _settle(tester);

    await tester.tap(find.text('Paul Kamga').last);
    await _settle(tester);
    await tester.tap(find.text('Solliciter Paul'));
    await _settle(tester);

    expect(h.sollicitations.created, isEmpty);
    expect(find.textContaining('Complétez votre profil'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Mes demandes : fiche numérotée et tampon de statut',
      (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(h.app());
    await tester.tap(find.text('Mes demandes'));
    await _settle(tester);
    expect(find.text('Chargement de vos fiches…'), findsOneWidget);

    h.sollicitations.controller.add([
      Sollicitation(
        id: '4213',
        prestataireId: 'p1',
        citoyenId: 'c1',
        nomCitoyen: 'Mbarga',
        numeroCitoyen: '+237677000000',
        statut: 'accepte',
        dateSollicitation: DateTime.now(),
        expert: const SollicitationExpert(
            nom: 'Kamga', prenom: 'Paul', services: ['menage']),
      ),
    ]);
    await _settle(tester);

    expect(find.text('N° 004213'), findsOneWidget);
    expect(find.text('EN ROUTE'), findsOneWidget);
    expect(find.textContaining('1 demande en cours'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Erreur de chargement : « Réessayer » se réabonne',
      (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(h.app());
    h.prestataires.controller.addError(Exception('réseau'));
    await _settle(tester);
    expect(
        find.text('Impossible de charger les prestataires.'), findsOneWidget);

    await tester.tap(find.text('Réessayer'));
    await _settle(tester);
    expect(h.prestataires.listens, 2);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in const [Size(360, 640), Size(412, 915)]) {
    testWidgets(
        'Liste des prestataires sans débordement en '
        '${size.width.toInt()}×${size.height.toInt()}', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = size * 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(h.app());
      h.prestataires.controller.add([_paul, _awa]);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
