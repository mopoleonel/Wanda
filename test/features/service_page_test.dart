import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wanda/core/providers/repository_providers.dart';
import 'package:wanda/core/router/app_routes.dart';
import 'package:wanda/core/theme/app_theme.dart';
import 'package:wanda/data/models/ajustement.dart';
import 'package:wanda/data/models/avis_prestataire.dart';
import 'package:wanda/data/models/categorie_service.dart';
import 'package:wanda/data/models/citoyen.dart';
import 'package:wanda/data/models/demande_menage.dart';
import 'package:wanda/data/models/particulier.dart';
import 'package:wanda/data/models/sollicitation.dart';
import 'package:wanda/data/repositories/auth_repository.dart';
import 'package:wanda/data/repositories/avis_repository.dart';
import 'package:wanda/data/repositories/demande_repository.dart';
import 'package:wanda/data/repositories/prestataire_repository.dart';
import 'package:wanda/data/repositories/profile_repository.dart';
import 'package:wanda/data/repositories/sollicitation_repository.dart';
import 'package:wanda/features/demande/demande_page.dart';
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

/// Ajustements et passages des demandes confirmées.
class _FakeDemandes extends Fake implements DemandeRepository {
  List<Ajustement> enAttente = const [];
  final reponses = <String, bool>{};
  final suivi = StreamController<void>.broadcast();

  @override
  Stream<void> changementsSuivi(String table) =>
      table == 'ajustements' ? suivi.stream : const Stream.empty();

  @override
  Future<List<Ajustement>> ajustements(List<String> ids) async =>
      enAttente.where((a) => ids.contains(a.sollicitationId)).toList();

  @override
  Future<List<DateTime>> passages(String id) async => [DateTime(2026, 10, 14)];

  @override
  Future<void> repondreAjustement(String id, {required bool accepte}) async =>
      reponses[id] = accepte;

  final photosDemandees = <String>[];
  @override
  Future<String> urlPhoto(String chemin) async {
    photosDemandees.add(chemin);
    return 'https://exemple.invalid/photo.jpg';
  }
}

class _Harness {
  final prestataires = _FakePrestataires();
  final sollicitations = _FakeSollicitations();
  final demandes = _FakeDemandes();

  /// Arguments reçus par l'écran de réservation (route remplacée).
  DemandeArgs? reservation;

  Widget app({Citoyen? citoyen = _citoyen}) {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const ServicePage()),
      GoRoute(
          path: AppRoutes.citoyenDemande,
          builder: (_, state) {
            reservation = state.extra as DemandeArgs?;
            return const Scaffold(body: Text('RÉSERVATION'));
          }),
    ]);
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuth()),
        profileRepositoryProvider.overrideWithValue(_FakeProfiles(citoyen)),
        avisRepositoryProvider.overrideWithValue(_FakeAvis()),
        prestataireRepositoryProvider.overrideWithValue(prestataires),
        sollicitationRepositoryProvider.overrideWithValue(sollicitations),
        demandeRepositoryProvider.overrideWithValue(demandes),
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
    expect(find.text('2 prestataires en ligne près de vous'), findsOneWidget);
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
    await tester.tap(find.text('Accueil'));
    await _settle(tester);

    expect(h.prestataires.listens, 1);
    expect(h.sollicitations.listens, 1);
    // Les prestataires restent affichés sans repasser par le chargement.
    expect(find.text('Recherche des prestataires en ligne…'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      "Accueil : un service sur la fiche ouvre la réservation, d'un toucher",
      (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(h.app());
    h.prestataires.controller.add([_paul, _awa]);
    await _settle(tester);

    // Plus de tuiles ni de « mieux notés » : les prestataires directement.
    expect(find.text('Réserver un service'), findsNothing);
    expect(find.text('Les mieux notés'), findsNothing);
    // Awa propose Linge et Déchets : un bouton par service, sur sa fiche.
    expect(find.bySemanticsLabel('Réserver : Linge'), findsOneWidget);
    await tester
        .tap(find.bySemanticsLabel('Réserver : Ramassage des poubelles'));
    await _settle(tester);
    expect(find.text('RÉSERVATION'), findsOneWidget);
    expect(h.reservation!.service, CategorieService.dechets);
    expect(h.reservation!.prestataire!.id, 'p2');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Fiche prestataire : réserver un de ses services, lui déjà choisi',
      (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(h.app());
    h.prestataires.controller.add([_awa]);
    await _settle(tester);

    await tester.tap(find.text('Awa Ngo').last);
    await _settle(tester);
    // Awa propose Linge et Déchets : un bouton par service.
    expect(find.text('Quel service ?'), findsOneWidget);
    expect(find.text('Réserver : Linge'), findsOneWidget);
    await tester.tap(find.text('Réserver : Déchets'));
    await _settle(tester);

    expect(h.reservation!.service, CategorieService.dechets);
    expect(h.reservation!.prestataire!.id, 'p2');
    expect(h.sollicitations.created, isEmpty,
        reason: 'plus de sollicitation sans prix');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Ajustement demandé : le client l\'accepte depuis sa fiche',
      (tester) async {
    tallScreen(tester);
    h.demandes.enAttente = [
      const Ajustement(
          id: 'aj1',
          sollicitationId: 'd9',
          minutesSupp: 60,
          produitsSupp: 0,
          motif: 'Une chambre de plus',
          photos: ['p1/aj/1.jpg'],
          prixSupp: 1200,
          statut: 'en_attente'),
    ];
    await tester.pumpWidget(h.app());
    await tester.tap(find.text('Mes demandes'));
    await _settle(tester);
    h.sollicitations.controller.add([
      Sollicitation.fromMap({
        'id': 'd9',
        'prestataire_id': 'p1',
        'citoyen_id': 'c1',
        'statut': 'accepte',
        'service': 'menage',
        'formule': 'abonnement',
        'frequence': 'hebdomadaire',
        'prix_passage': 5400,
        'prix_total': 21600,
        'date_souhaitee': '2026-10-22',
        'creneau': 'matin',
      }),
    ]);
    await _settle(tester);

    expect(find.text('AJUSTEMENT'), findsOneWidget);
    expect(find.text('« Une chambre de plus »'), findsOneWidget);
    expect(find.textContaining('1 passage effectué'), findsOneWidget);
    expect(find.textContaining('Prévu jeu. 22/10, matin'), findsOneWidget);

    // La photo du prestataire justifie le supplément (URL signée).
    await tester.tap(find.text('Voir la photo du prestataire'));
    await _settle(tester);
    expect(h.demandes.photosDemandees, ['p1/aj/1.jpg']);
    await tester.tap(find.byTooltip('Fermer'));
    await _settle(tester);
    await tester.tap(find.text('Accepter'));
    await _settle(tester);
    expect(h.demandes.reponses, {'aj1': true});
    expect(find.text('AJUSTEMENT'), findsNothing);
    // Nouveau prix total : la fiche est relue.
    expect(h.sollicitations.listens, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Ajustement demandé pendant que le client regarde : affiché',
      (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(h.app());
    await tester.tap(find.text('Mes demandes'));
    await _settle(tester);
    h.sollicitations.controller.add([
      Sollicitation.fromMap({
        'id': 'd9',
        'prestataire_id': 'p1',
        'citoyen_id': 'c1',
        'statut': 'accepte',
        'service': 'linge',
        'formule': 'ponctuelle',
        'prix_total': 2600,
      }),
    ]);
    await _settle(tester);
    expect(find.text('AJUSTEMENT'), findsNothing);

    h.demandes.enAttente = [
      const Ajustement(
          id: 'aj2',
          sollicitationId: 'd9',
          minutesSupp: 30,
          produitsSupp: 500,
          motif: 'Draps en plus',
          photos: [],
          prixSupp: 1100,
          statut: 'en_attente'),
    ];
    h.demandes.suivi.add(null);
    await _settle(tester);
    expect(find.text('AJUSTEMENT'), findsOneWidget);
    expect(find.text('« Draps en plus »'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Demande refusée : « Choisir un autre prestataire » la reprend',
      (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(h.app());
    await tester.tap(find.text('Mes demandes'));
    await _settle(tester);
    h.sollicitations.controller.add([
      Sollicitation.fromMap({
        'id': 'd8',
        'prestataire_id': 'p1',
        'citoyen_id': 'c1',
        'statut': 'refuse',
        'motif_refus': 'Pas disponible mardi',
        'service': 'linge',
        'formule': 'ponctuelle',
        'reponses': {'paniers': 3},
        'photos': ['c1/d/1.jpg'],
        'prix_total': 5000,
        'date_souhaitee': '2026-12-02',
        'creneau': 'apres_midi',
      }),
    ]);
    await _settle(tester);

    expect(find.text('REFUSÉ'), findsOneWidget);
    expect(find.text('« Pas disponible mardi »'), findsOneWidget);
    await tester.tap(find.text('Choisir un autre prestataire'));
    await _settle(tester);
    expect(h.reservation!.reprise!.entier('paniers'), 3);
    expect(h.reservation!.photosEnvoyees, ['c1/d/1.jpg']);
    expect(h.reservation!.exclu, 'p1');
    expect(h.reservation!.creneau, Creneau.apresMidi);
    expect(h.reservation!.date, DateTime(2026, 12, 2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("Accueil : la demande en cours se suit d'un coup d'œil",
      (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(h.app());
    h.sollicitations.controller.add([
      Sollicitation.fromMap({
        'id': 'e0ff8a0e',
        'prestataire_id': 'p1',
        'citoyen_id': 'c1',
        'statut': 'accepte',
        'service': 'menage',
        'formule': 'ponctuelle',
        'date_souhaitee': '2026-10-25',
        'creneau': 'matin',
      }),
    ]);
    await _settle(tester);

    expect(find.text('Ménage · N° E0FF8A'), findsOneWidget);
    expect(find.text('Confirmé pour dim. 25/10, matin'), findsOneWidget);
    await tester.tap(find.text('Confirmé pour dim. 25/10, matin'));
    await _settle(tester);
    expect(find.textContaining('1 demande en cours'), findsOneWidget);
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
    expect(find.text('CONFIRMÉ'), findsOneWidget);
    expect(find.text('Annuler la demande'), findsOneWidget);
    expect(find.textContaining('1 demande en cours'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Mission terminée : « Noter et clore » sans « Annuler »',
      (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(h.app());
    await tester.tap(find.text('Mes demandes'));
    await _settle(tester);
    h.sollicitations.controller.add([
      Sollicitation(
        id: '50930',
        prestataireId: 'p1',
        citoyenId: 'c1',
        nomCitoyen: 'Mbarga',
        numeroCitoyen: '+237677000000',
        statut: 'termine',
        dateSollicitation: DateTime.now(),
        dateFin: DateTime.now(),
        expert: const SollicitationExpert(
            nom: 'Kamga', prenom: 'Paul', services: ['menage']),
      ),
    ]);
    await _settle(tester);

    expect(find.text('TERMINÉ'), findsOneWidget);
    expect(find.text('Noter et clore'), findsOneWidget);
    expect(find.text('Annuler la demande'), findsNothing);
    expect(find.textContaining('1 mission terminée : notez'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Le prestataire confirme : le client est prévenu, avec « Voir »',
      (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(h.app());
    Sollicitation fiche(String statut) => Sollicitation(
          id: 'cafe01',
          prestataireId: 'p1',
          citoyenId: 'c1',
          nomCitoyen: 'Mbarga',
          numeroCitoyen: '+237677000000',
          statut: statut,
          dateSollicitation: DateTime.now(),
          expert: const SollicitationExpert(
              nom: 'Kamga', prenom: 'Paul', services: ['menage']),
        );
    h.sollicitations.controller.add([fiche('en_attente')]);
    await _settle(tester);
    expect(find.textContaining('a confirmé'), findsNothing);

    h.sollicitations.controller.add([fiche('accepte')]);
    await _settle(tester);
    expect(
        find.text('Paul a confirmé votre demande N° CAFE01.'), findsOneWidget);
    await tester.tap(find.text('Voir'));
    await _settle(tester);
    expect(find.textContaining('1 demande en cours'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Fiches classées : repliées dans un historique', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(h.app());
    await tester.tap(find.text('Mes demandes'));
    await _settle(tester);
    Sollicitation fiche(String id, String statut) => Sollicitation.fromMap({
          'id': id,
          'prestataire_id': 'p1',
          'citoyen_id': 'c1',
          'statut': statut,
          'service': 'menage',
          'formule': 'ponctuelle',
        });
    h.sollicitations.controller
        .add([fiche('aaaa01', 'accepte'), fiche('bbbb02', 'archive')]);
    await _settle(tester);

    expect(find.text('N° AAAA01'), findsOneWidget);
    expect(find.text('N° BBBB02'), findsNothing);
    await tester.tap(find.text('Historique · 1 fiche'));
    await _settle(tester);
    expect(find.text('N° BBBB02'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Mes demandes : tirer pour rafraîchir se réabonne',
      (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(h.app());
    await tester.tap(find.text('Mes demandes'));
    await _settle(tester);
    h.sollicitations.controller.add(const []);
    await _settle(tester);

    tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(h.sollicitations.listens, 2);
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
