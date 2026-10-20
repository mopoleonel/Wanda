import 'package:flutter_test/flutter_test.dart';
import 'package:wanda/data/models/particulier.dart';

Particulier _p(
        {String nom = 'Kamga',
        String prenom = 'Paul',
        String metier = 'Plombier',
        String? photo = 'https://x/p.jpg'}) =>
    Particulier(
        id: '1',
        nom: nom,
        prenom: prenom,
        telephone: '+237699000000',
        servicePropose: metier,
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
    final p = _p(nom: ' ', prenom: '', metier: '', photo: null);
    expect(
        p.profilManquant, ['photo professionnelle', 'nom', 'prénom', 'métier']);
    expect(Particulier.profilElements, 4);
  });

  test('visible des citoyens : nom, prénom et métier suffisent', () {
    expect(_p(photo: null).infosVisibiliteManquantes, isEmpty);
    // Inscrit avec son seul numéro.
    expect(_p(nom: '', prenom: '', metier: '').infosVisibiliteManquantes,
        ['nom', 'prénom', 'métier']);
  });

  test('jours restants arrondis au jour supérieur', () {
    final now = DateTime(2026, 10, 13, 12);
    Particulier withEnd(DateTime? end) => Particulier(
        id: '1',
        nom: 'a',
        prenom: 'b',
        telephone: '',
        servicePropose: 'Plombier',
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
        servicePropose: 'Plombier',
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

    test('nom, prénom, métier et téléphone ; pas la photo', () {
      expect(Particulier.champsFiges,
          ['nom', 'prénom', 'métier', 'téléphone']);
      expect(Particulier.champsFiges, isNot(contains('photo professionnelle')));
    });
  });
}
