// Parcours complet contre un serveur Django réel (dépôts de l'app, vrai HTTP).
//
// Lancement (serveur de développement démarré, numéros de test configurés
// dans backend/.env : OTP_NUMEROS_TEST=+237690000001=123456,+237690000002=123456) :
//   flutter test test_e2e --dart-define=E2E_API=http://127.0.0.1:8000/api/
//
// Sans E2E_API, le test est ignoré (il ne tourne pas avec `flutter test`).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wanda/core/api/api_client.dart';
import 'package:wanda/core/api/session.dart';
import 'package:wanda/data/models/categorie_service.dart';
import 'package:wanda/data/models/citoyen.dart';
import 'package:wanda/data/models/demande_menage.dart';
import 'package:wanda/data/pricing/tarification.dart';
import 'package:wanda/data/repositories/auth_repository.dart';
import 'package:wanda/data/repositories/avis_repository.dart';
import 'package:wanda/data/repositories/demande_repository.dart';
import 'package:wanda/data/repositories/prestataire_repository.dart';
import 'package:wanda/data/repositories/profile_repository.dart';
import 'package:wanda/data/repositories/sollicitation_repository.dart';

const _api = String.fromEnvironment('E2E_API');
const _code = String.fromEnvironment('E2E_CODE', defaultValue: '123456');

ApiClient _client() =>
    ApiClient(baseUrl: _api, session: GestionSession(StockageSessionMemoire()));

void main() {
  test('client et prestataire : demande, acceptation, ajustement, note',
      () async {
    final presta = _client();
    final client = _client();

    // 1. Prestataire : connexion, profil, essai gratuit, en ligne.
    final authP = AuthRepository(presta);
    await authP.sendWhatsAppOtp('+237690000001');
    final idP = await authP.verifyWhatsAppOtp(
        phone: '+237690000001', code: _code, typeCompte: 'particulier');
    final profilP = ProfileRepository(presta);
    if (authP.dernierCompteNouveau ||
        await profilP.fetchParticulier(idP) == null) {
      await profilP.createParticulier(id: idP, telephone: '+237690000001');
    }
    await profilP.updateParticulierInfo(
        id: idP,
        nom: 'Essai',
        prenom: 'Prestataire',
        telephone: '+237690000001',
        services: ['menage']);
    var moiP = await profilP.fetchParticulier(idP);
    if (moiP!.abonnementExpireAt == null ||
        moiP.abonnementExpireAt!.isBefore(DateTime.now())) {
      await profilP.startFreeTrial(idP, duration: const Duration(days: 30));
    }
    await PrestataireRepository(presta)
        .setAvailability(idP, true, latitude: 4.05, longitude: 9.7);

    // 2. Client : connexion, il voit le prestataire.
    final authC = AuthRepository(client);
    await authC.sendWhatsAppOtp('+237690000002');
    final idC = await authC.verifyWhatsAppOtp(
        phone: '+237690000002', code: _code, typeCompte: 'citoyen');
    // Comme l'écran de réservation : le nom est demandé s'il manque.
    final profilC = ProfileRepository(client);
    final moiC = await profilC.fetchCitoyen(idC);
    await profilC.updateCitoyen(Citoyen(
        citoyenId: idC,
        nom: 'Client essai',
        prenom: moiC?.prenom ?? '',
        email: moiC?.email ?? '',
        telephone: '+237690000002'));
    final dispo = await PrestataireRepository(client).disponiblesPour('menage');
    expect(dispo.map((p) => p.id), contains(idP));

    // 3. Prix : le calcul de l'app et celui du serveur concordent.
    final tarifs = await TarifRepository(client).charger();
    final demande =
        DemandeMenage.initiale(CategorieService.menage).avec(Q.chambres, 3);
    final local = calculerPrix(demande, tarifs);
    final serveur = await DemandeRepository(client).prixServeur(demande);
    expect(serveur.prixTotal, local.prixTotal);

    // 4. Demande envoyée.
    // Photo envoyée comme dans l'app (dossier privé du client).
    final photo = await DemandeRepository(client).envoyerPhoto(
        File('assets/images/icone_app.png'),
        dossier: 'demande-${DateTime.now().millisecondsSinceEpoch}');
    final idD = await DemandeRepository(client).creer(
      prestataireId: idP,
      demande: demande,
      photos: [photo],
      date: DateTime.now().add(const Duration(days: 1)),
      creneau: Creneau.matin,
    );

    // 5. Le prestataire la reçoit et l'accepte.
    final recues =
        await SollicitationRepository(presta).fetchForPrestataire(idP);
    expect(recues.map((s) => s.id), contains(idD));
    await SollicitationRepository(presta).updateStatus(idD, 'accepte');

    // 6. Ajustement demandé sur place, accepté par le client.
    await DemandeRepository(presta).demanderAjustement(
        sollicitationId: idD,
        minutes: 30,
        produits: 0,
        motif: 'Cuisine très sale');
    final ajust = await DemandeRepository(client).ajustements([idD]);
    expect(ajust, hasLength(1));
    expect(ajust.single.prixSupp, greaterThan(0));
    await DemandeRepository(client)
        .repondreAjustement(ajust.single.id, accepte: true);

    // 7. Mission terminée, le client note.
    await SollicitationRepository(presta).updateStatus(idD, 'termine');
    final suivi =
        await SollicitationRepository(client).streamForCitoyen(idC).first;
    final mission = suivi.firstWhere((s) => s.id == idD);
    expect(mission.statut, 'termine');
    expect(mission.prixTotal, local.prixTotal + ajust.single.prixSupp);
    await AvisRepository(client).create(
        sollicitationId: idD, prestataireId: idP, citoyenId: idC, note: 5);
    final note = await AvisRepository(client).averageForPrestataire(idP);
    expect(note.count, greaterThan(0));

    // 8. Une mission terminée ne peut pas être rouverte par le client.
    await expectLater(
        SollicitationRepository(client).updateStatus(idD, 'accepte'),
        throwsA(anything));

    await PrestataireRepository(presta).setAvailability(idP, false);
    moiP = await profilP.fetchParticulier(idP);
    expect(moiP!.isAvailable, isFalse);
  },
      skip: _api.isEmpty ? 'E2E_API non défini' : false,
      timeout: const Timeout(Duration(minutes: 2)));
}
