import 'package:flutter_test/flutter_test.dart';
import 'package:wanda/data/models/particulier.dart';

Particulier _p(
        {String nom = 'Kamga',
        String prenom = 'Paul',
        List<String> services = const ['menage'],
        String? photo = 'https://x/p.jpg'}) =>
    Particulier(
        id: '1',
        nom: nom,
        prenom: prenom,
        telephone: '+237699000000',
        services: services,
        photoProUrl: photo);

void main() {
  test('profil complet : rien ne manque', () {
    expect(_p().profilComplet, isTrue);
    expect(_p().profilManquant, isEmpty);
  });

  test('inscription par téléphone : la photo manque', () {
    final p = _p(photo: '');
    expect(p.profilComplet, isFalse);
    expect(p.profilManquant, ['photo professionnelle']);
    expect(_p(photo: null).profilManquant, ['photo professionnelle']);
  });

  test('champs vides ou blancs comptés comme manquants', () {
    final p = _p(nom: ' ', prenom: '', services: const [], photo: null);
    expect(p.profilManquant,
        ['photo professionnelle', 'nom', 'prénom', 'services proposés']);
    expect(Particulier.profilElements, 4);
  });

  test('visible des citoyens : nom, prénom et un service suffisent', () {
    expect(_p(photo: null).infosVisibiliteManquantes, isEmpty);
    // Inscrit avec son seul numéro.
    expect(
        _p(nom: '', prenom: '', services: const []).infosVisibiliteManquantes,
        ['nom', 'prénom', 'services proposés']);
  });

  test('jours restants arrondis au jour supérieur', () {
    final now = DateTime(2026, 10, 13, 12);
    Particulier withEnd(DateTime? end) => Particulier(
        id: '1',
        nom: 'a',
        prenom: 'b',
        telephone: '',
        services: const ['menage'],
        abonnementExpireAt: end);
    expect(
        withEnd(now.add(const Duration(days: 14, seconds: -5)))
            .joursRestants(now),
        14);
    expect(withEnd(now.add(const Duration(hours: 3))).joursRestants(now), 1);
    expect(
        withEnd(now.subtract(const Duration(hours: 1))).joursRestants(now), 0);
    expect(withEnd(null).joursRestants(now), 0);
  });

  group('identité figée', () {
    Particulier certifie(bool v) => Particulier(
        id: '1',
        nom: 'Kamga',
        prenom: 'Paul',
        telephone: '+237699000000',
        services: const ['menage'],
        identiteVerifiee: v);

    test("libre tant que rien n'est envoyé", () {
      expect(certifie(false).identiteFigee(), isFalse);
    });

    test('figée pendant la vérification', () {
      expect(certifie(false).identiteFigee(verificationEnCours: true), isTrue);
    });

    test('figée une fois certifiée', () {
      expect(certifie(true).identiteFigee(), isTrue);
    });

    test('nom, prénom et téléphone ; pas la photo ni les services', () {
      expect(Particulier.champsFiges, ['nom', 'prénom', 'téléphone']);
      expect(Particulier.champsFiges, isNot(contains('photo professionnelle')));
    });

    test('compte libre : services modifiables dans tous les sens', () {
      final p = certifie(false);
      expect(p.servicesModifiables(const ['linge']), isTrue);
      expect(p.servicesModifiables(const []), isTrue);
    });

    test('compte figé : on peut ajouter un service, pas en retirer', () {
      final p = certifie(true);
      expect(p.servicesModifiables(const ['menage', 'linge']), isTrue);
      expect(p.servicesModifiables(const ['menage']), isTrue);
      expect(p.servicesModifiables(const ['linge']), isFalse);
      expect(
          certifie(false)
              .servicesModifiables(const ['linge'], verificationEnCours: true),
          isFalse);
    });
  });
}
