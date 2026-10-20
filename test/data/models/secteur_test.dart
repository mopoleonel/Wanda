import 'package:flutter_test/flutter_test.dart';
import 'package:wanda/data/models/secteur.dart';

void main() {
  group('secteurPourType', () {
    test('types de l\'écran de signalement', () {
      expect(secteurPourType("Fuite d'eau"), secteurHydraulique);
      expect(secteurPourType('Électricité'), secteurElectricite);
      expect(secteurPourType("Dépôt d'ordures"), secteurEnvironnement);
      expect(secteurPourType('Autre (IA)'), secteurSecurite);
    });

    test('types libres détectés par l\'IA, accents et majuscules ignorés', () {
      expect(secteurPourType('Nid de poule'), secteurVoirie);
      expect(secteurPourType('Route effondrée'), secteurVoirie);
      expect(secteurPourType('Câble électrique arraché'), secteurElectricite);
      expect(secteurPourType('LAMPADAIRE en panne'), secteurElectricite);
      expect(secteurPourType('Canalisation bouchée'), secteurHydraulique);
      expect(secteurPourType('Déchets plastiques'), secteurEnvironnement);
    });

    test('« eau » ne reconnaît pas « réseau » ni « bateau »', () {
      expect(
          secteurPourType('Réseau électrique endommagé'), secteurElectricite);
      expect(secteurPourType('Bateau échoué'), secteurSecurite);
    });

    test('inconnu : envoyé à la Sécurité Publique plutôt qu\'à personne', () {
      expect(secteurPourType('Animal errant'), secteurSecurite);
      expect(secteurPourType(''), secteurSecurite);
    });
  });

  group('typesDuSecteur', () {
    test('types de l\'écran rattachés au secteur', () {
      expect(typesDuSecteur(secteurHydraulique), ["Fuite d'eau"]);
      expect(typesDuSecteur(secteurSecurite),
          containsAll(['Sécurité Publique', 'Autre (IA)']));
    });

    test('secteur inconnu : lui-même', () {
      expect(typesDuSecteur('Autre secteur'), ['Autre secteur']);
    });

    test('chaque secteur proposé reçoit au moins un type', () {
      for (final s in secteursActivite) {
        expect(typesDuSecteur(s), isNot([s]), reason: s);
      }
    });
  });
}
