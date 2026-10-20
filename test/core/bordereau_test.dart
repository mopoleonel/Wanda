import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanda/core/theme/app_theme.dart';
import 'package:wanda/core/widgets/bordereau.dart';
import 'package:wanda/data/models/categorie_service.dart';
import 'package:wanda/data/models/avis_prestataire.dart';

Widget _wrap(Widget child, {bool disableAnimations = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  group('ficheNumber', () {
    test('id numérique complété sur 6 chiffres', () {
      expect(ficheNumber('4213'), 'N° 004213');
      expect(ficheNumber('1234567'), 'N° 1234567');
    });

    test('uuid : 6 premiers caractères en capitales, sans tirets', () {
      expect(ficheNumber('12a5fc3e-91b0-4c11'), 'N° 12A5FC');
    });

    test('id court non numérique gardé tel quel', () {
      expect(ficheNumber('ab-c'), 'N° ABC');
    });
  });

  group('distanceLabel', () {
    test('en mètres sous 1 km', () => expect(distanceLabel(849.6), '850 m'));
    test('en km avec virgule décimale', () {
      expect(distanceLabel(5800), '5,8 km');
      expect(distanceLabel(1000), '1,0 km');
    });
  });

  group('sinceLabel', () {
    final now = DateTime.now();
    test("à l'instant", () => expect(sinceLabel(now), "à l'instant"));
    test('minutes', () {
      expect(sinceLabel(now.subtract(const Duration(minutes: 12))),
          'il y a 12 min');
    });
    test('heures', () {
      expect(sinceLabel(now.subtract(const Duration(hours: 3, minutes: 5))),
          'il y a 3 h');
    });
    test('jours', () {
      expect(sinceLabel(now.subtract(const Duration(days: 8))), 'il y a 8 j');
    });
  });

  group('FicheStatus', () {
    test('sollicitation : chaque statut a son tampon et son encre', () {
      expect(FicheStatus.sollicitation('en_attente').label, 'REÇU');
      expect(
          FicheStatus.sollicitation('en_attente').ink, AppColors.stampViolet);
      expect(FicheStatus.sollicitation('accepte').label, 'CONFIRMÉ');
      expect(FicheStatus.sollicitation('refuse').label, 'REFUSÉ');
      expect(FicheStatus.sollicitation('refuse').ink, AppColors.danger);
      expect(FicheStatus.sollicitation('accepte').ink, AppColors.progress);
      expect(FicheStatus.sollicitation('termine').label, 'TERMINÉ');
      expect(FicheStatus.sollicitation('termine').ink, AppColors.done);
      expect(FicheStatus.sollicitation('archive').label, 'CLASSÉ');
      expect(FicheStatus.sollicitation('annule').ink, AppColors.danger);
    });

    test('signalement : statut inconnu retombe sur REÇU', () {
      expect(FicheStatus.signalement('en_cours').label, 'EN COURS');
      expect(FicheStatus.signalement('resolu').label, 'RÉSOLU');
      expect(FicheStatus.signalement('rejete').label, 'REJETÉ');
      expect(FicheStatus.signalement('???').label, 'REÇU');
    });
  });

  group('ServiceStyle', () {
    test('service connu : sa copie carbone fixe', () {
      final s = ServiceStyle.of('menage');
      expect(s.label, 'Ménage');
      expect(s.libelle, 'Ménage et nettoyage');
      expect(s.icon, Icons.cleaning_services_rounded);
      expect(s.tint, const Color(0xFFD8E7F8));
    });

    test('chaque catégorie a sa propre copie carbone', () {
      final styles = CategorieService.values.map(ServiceStyle.ofCategorie);
      expect(styles.map((s) => s.tint).toSet(), hasLength(4));
      expect(styles.map((s) => s.icon).toSet(), hasLength(4));
    });

    test('services d\'un prestataire : style de la première catégorie', () {
      expect(ServiceStyle.ofServices(['linge', 'menage']).label, 'Linge');
      expect(ServiceStyle.ofServices(const []), same(ServiceStyle.tous));
    });

    test('vide ou « Tous » : style générique', () {
      expect(ServiceStyle.of(null), same(ServiceStyle.tous));
      expect(ServiceStyle.of(''), same(ServiceStyle.tous));
      expect(ServiceStyle.of('tous'), same(ServiceStyle.tous));
    });

    test('ancien métier ou code inconnu : couleurs neutres', () {
      final s = ServiceStyle.of('Plombier');
      expect(s.label, 'Plombier');
      expect(s.tint, AppColors.surfaceSunk);
    });

    test('la liste des onglets commence par « Tous »', () {
      expect(ServiceStyle.codes,
          ['tous', 'menage', 'linge', 'dechets', 'nuisibles']);
    });
  });

  testWidgets('StatusStamp annonce le statut aux lecteurs d’écran',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester
        .pumpWidget(_wrap(StatusStamp(FicheStatus.sollicitation('accepte'))));
    await tester.pumpAndSettle();

    expect(find.text('CONFIRMÉ'), findsOneWidget);
    expect(find.bySemanticsLabel('Statut : confirmé'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('StatusStamp : pas d’animation si le système les désactive',
      (tester) async {
    await tester.pumpWidget(_wrap(
        StatusStamp(FicheStatus.signalement('resolu')),
        disableAnimations: true));

    expect(find.byType(AnimatedSwitcher), findsNothing);
    expect(find.text('RÉSOLU'), findsOneWidget);
  });

  testWidgets('StatusStamp : le nouveau tampon remplace l’ancien',
      (tester) async {
    await tester.pumpWidget(
        _wrap(StatusStamp(FicheStatus.sollicitation('en_attente'))));
    await tester.pumpAndSettle();
    await tester
        .pumpWidget(_wrap(StatusStamp(FicheStatus.sollicitation('termine'))));
    await tester.pumpAndSettle();

    expect(find.text('REÇU'), findsNothing);
    expect(find.text('TERMINÉ'), findsOneWidget);
  });

  testWidgets('ServiceTag affiche le libellé de repli sans service',
      (tester) async {
    await tester.pumpWidget(_wrap(const Column(children: [
      ServiceTag(null),
      ServiceTag('', emptyLabel: 'Services à choisir'),
      ServiceTag('nuisibles'),
    ])));

    expect(find.text('Prestataire'), findsOneWidget);
    expect(find.text('Services à choisir'), findsOneWidget);
    expect(find.text('Nuisibles'), findsOneWidget);
  });

  testWidgets('RatingInline : « Nouveau » sans avis, note française sinon',
      (tester) async {
    await tester.pumpWidget(_wrap(const Column(children: [
      RatingInline(RatingSummary.empty),
      RatingInline(RatingSummary(average: 4.56, count: 12)),
    ])));

    expect(find.text('Nouveau'), findsOneWidget);
    expect(find.text('4,6 (12)'), findsOneWidget);
  });

  testWidgets('IdPhoto sans URL affiche l’icône de repli', (tester) async {
    await tester.pumpWidget(_wrap(const IdPhoto(url: null)));
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
  });

  testWidgets('Letterhead : titre, contexte et bouton retour accessible',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Letterhead(
          title: 'Mes demandes',
          overline: 'Espace citoyen',
          subtitle: '3 fiches en cours',
          showBack: true,
        ),
      ),
    ));

    expect(find.text('Mes demandes'), findsOneWidget);
    expect(find.text('Espace citoyen'), findsOneWidget);
    expect(find.text('3 fiches en cours'), findsOneWidget);
    expect(find.byTooltip('Retour'), findsOneWidget);
  });
}
