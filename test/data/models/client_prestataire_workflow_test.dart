import 'package:flutter_test/flutter_test.dart';
import 'package:wanda/data/models/ajustement.dart';
import 'package:wanda/data/repositories/avis_repository.dart';
import 'package:wanda/data/models/categorie_service.dart';
import 'package:wanda/data/models/citoyen.dart';
import 'package:wanda/data/models/demande_menage.dart';
import 'package:wanda/data/models/particulier.dart';
import 'package:wanda/data/models/sollicitation.dart';
import 'package:wanda/data/models/verification_identite.dart';
import 'package:wanda/data/pricing/tarification.dart';

void main() {
  group('Workflow Client : Réservation et cycle de vie', () {
    test('Création du profil citoyen et sérialisation', () {
      const c = Citoyen(
        citoyenId: 'c-uuid-1',
        nom: 'Mbarga',
        prenom: 'Lucie',
        email: 'lucie@wanda.app',
        telephone: '+237690000002',
      );
      final map = c.toUpdateMap();
      expect(map['nom'], 'Mbarga');
      expect(map['prenom'], 'Lucie');
      expect(map['email'], 'lucie@wanda.app');
      expect(map['telephone'], '+237690000002');

      // Email vide devient null pour respecter les contraintes de base
      const cSansEmail = Citoyen(
        citoyenId: 'c-uuid-2',
        nom: 'Kenfack',
        prenom: 'Alain',
        email: '   ',
        telephone: '+237690000003',
      );
      expect(cSansEmail.toUpdateMap()['email'], isNull);
    });

    test('Configuration du besoin client et calcul prix ponctuel', () {
      const demande = DemandeMenage(
        service: CategorieService.menage,
        formule: Formule.ponctuelle,
        reponses: {
          Q.chambres: 2,
          Q.salons: 1,
          Q.cuisines: 1,
          Q.doucheWc: 1,
          Q.etat: 'normal',
        },
        produitsFournis: false,
      );

      final estimation = calculerPrix(demande);
      // 2*30 + 1*40 + 1*45 + 1*30 = 175 min
      expect(estimation.minutes, 175);
      // Main d'oeuvre: (175 * 1200 + 30) ~/ 60 = 3500 FCFA
      // Déplacement: 1000 FCFA -> Total 4500 FCFA
      expect(estimation.mainOeuvre, 3500);
      expect(estimation.deplacement, 1000);
      expect(estimation.prixTotal, 4500);
      expect(estimation.passages, 1);
    });

    test('Configuration client avec abonnement hebdomadaire', () {
      const demande = DemandeMenage(
        service: CategorieService.linge,
        formule: Formule.abonnement,
        frequence: Frequence.hebdomadaire,
        reponses: {
          Q.paniers: 2,
          Q.repassage: true,
          Q.piecesRepassage: 10,
        },
        produitsFournis: true,
      );

      final est = calculerPrix(demande);
      expect(est.passages, 4); // 4 passages par mois
      expect(est.prixTotal, est.prixPassage * 4);
    });
  });

  group('Workflow Prestataire : Profil, visibilité et certification', () {
    test('Contrôle des informations requises pour être en ligne', () {
      const prestaIncomplet = Particulier(
        id: 'p-1',
        nom: '',
        prenom: '',
        telephone: '+237690000001',
        services: [],
      );
      expect(prestaIncomplet.profilComplet, isFalse);
      expect(prestaIncomplet.infosVisibiliteManquantes,
          containsAll(['nom', 'prénom', 'services proposés']));

      final prestaPret = Particulier(
        id: 'p-1',
        nom: 'Essai',
        prenom: 'Testeur',
        telephone: '+237690000001',
        services: const ['menage', 'linge'],
        photoProUrl: 'https://cdn.wanda.app/photo.jpg',
        isAvailable: true,
        abonnementExpireAt: DateTime.now().add(const Duration(days: 14)),
      );
      expect(prestaPret.profilComplet, isTrue);
      expect(prestaPret.infosVisibiliteManquantes, isEmpty);
      expect(prestaPret.joursRestants(), 14);
    });

    test('Identité figée dès que la certification est en cours ou validée', () {
      const prestaNonCertifie = Particulier(
        id: 'p-1',
        nom: 'Kamga',
        prenom: 'Paul',
        telephone: '+237690000001',
        services: ['menage'],
        identiteVerifiee: false,
      );
      expect(prestaNonCertifie.identiteFigee(), isFalse);
      expect(
          prestaNonCertifie.identiteFigee(verificationEnCours: true), isTrue);

      const prestaCertifie = Particulier(
        id: 'p-1',
        nom: 'Kamga',
        prenom: 'Paul',
        telephone: '+237690000001',
        services: ['menage'],
        identiteVerifiee: true,
      );
      expect(prestaCertifie.identiteFigee(), isTrue);

      // Peut ajouter des services, mais pas en retirer
      expect(
          prestaCertifie.servicesModifiables(['menage', 'linge'],
              verificationEnCours: true),
          isTrue);
      expect(
          prestaCertifie
              .servicesModifiables(['linge'], verificationEnCours: true),
          isFalse);
    });

    test('Statuts de vérification d\'identité', () {
      final v1 = VerificationIdentite.fromMap(const {
        'id': 'v-1',
        'statut': 'en_attente',
        'created_at': '2026-11-16T12:00:00Z',
      });
      expect(v1.statut, VerificationStatut.enAttente);

      final v2 = VerificationIdentite.fromMap(const {
        'id': 'v-2',
        'statut': 'valide',
      });
      expect(v2.statut, VerificationStatut.valide);

      final v3 = VerificationIdentite.fromMap(const {
        'id': 'v-3',
        'statut': 'rejete',
        'motif_rejet': 'Photo CNI floue',
      });
      expect(v3.statut, VerificationStatut.rejete);
      expect(v3.motifRejet, 'Photo CNI floue');
    });
  });

  group('Interaction Client-Prestataire & Ajustements & Avis', () {
    test('Désérialisation d\'une sollicitation complète et calcul date', () {
      final nowUtc = DateTime.now().toUtc();
      final sol = Sollicitation.fromMap({
        'id': 'sol-12345678',
        'prestataire_id': 'p-1',
        'citoyen_id': 'c-1',
        'nom_citoyen': 'Mbarga',
        'prenom_citoyen': 'Lucie',
        'numero_citoyen': '+237690000002',
        'date_sollicitation': nowUtc.toIso8601String(),
        'statut': 'en_attente',
        'service': 'menage',
        'formule': 'ponctuelle',
        'prix_total': 4500,
        'minutes_estimees': 175,
        'date_souhaitee': '2026-11-20',
        'creneau': 'matin',
        'photos': ['c-1/d1/1.jpg', 'c-1/d1/2.jpg'],
        'reponses': {'chambres': 2, 'salons': 1},
      });

      expect(sol.estDemandeMenage, isTrue);
      expect(sol.prixTotal, 4500);
      expect(sol.photos.length, 2);
      expect(sol.quand, contains('matin'));
      expect(sol.demande?.service, CategorieService.menage);
    });

    test('Cycle de vie d\'un ajustement', () {
      final ajMap = {
        'id': 'aj-1',
        'sollicitation_id': 'sol-1',
        'minutes_supp': 30,
        'produits_supp': 0,
        'motif': 'Salon plus encombré que prévu',
        'photos': ['p-1/aj/1.jpg'],
        'prix_supp': 600,
        'statut': 'en_attente',
        'created_at': DateTime.now().toIso8601String(),
      };

      final aj = Ajustement.fromMap(ajMap);
      expect(aj.enAttente, isTrue);
      expect(aj.prixSupp, 600);
      expect(aj.minutesSupp, 30);
      expect(aj.photos, contains('p-1/aj/1.jpg'));
    });

    test('Agrégation des avis et note moyenne', () {
      final reviews = [
        {'prestataire_id': 'p-1', 'note': 5},
        {'prestataire_id': 'p-1', 'note': 4},
        {'prestataire_id': 'p-2', 'note': 3},
      ];

      final ratings = aggregateRatings(reviews);
      expect(ratings['p-1']?.average, 4.5);
      expect(ratings['p-1']?.count, 2);
      expect(ratings['p-2']?.average, 3.0);
      expect(ratings['p-2']?.count, 1);
    });
  });
}
