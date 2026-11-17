import 'dart:io';

import '../../core/api/api_client.dart';
import '../../core/error/error_mapper.dart';
import '../api/adaptateurs.dart';
import '../models/citoyen.dart';
import '../models/entreprise.dart';
import '../models/particulier.dart';

/// Profils du compte connecté (citoyen, prestataire, entreprise).
///
/// L'API ne donne accès qu'au profil de l'utilisateur connecté : les
/// identifiants passés en paramètre ne servent qu'à garder les mêmes appels
/// dans les écrans.
class ProfileRepository {
  final ApiClient _api;
  ProfileRepository(this._api);

  /// Type d'un compte ouvert sans type (premier code dans l'espace
  /// prestataire) : crée le profil vide correspondant. Une entreprise passe
  /// par [createEntreprise].
  Future<void> createProfileEntry(String userId, String userType) async {
    if (userType == 'entreprise') return;
    try {
      await _api.post('moi/type', {'type_compte': userType});
      await _api.session.majType(userType);
    } catch (e, st) {
      throw mapError('ProfileRepository.createProfileEntry', e, st);
    }
  }

  // --- Citoyen ---

  /// Le profil citoyen est créé avec le compte (code WhatsApp) : il ne
  /// reste qu'à s'assurer qu'il existe.
  Future<void> createCitoyen({
    required String citoyenId,
    required String telephone,
    String? nom,
    String? prenom,
    String? email,
  }) =>
      createProfileEntry(citoyenId, 'citoyen');

  Future<Citoyen?> fetchCitoyen(String citoyenId) async {
    try {
      final d = await _api.get('moi/citoyen');
      return Citoyen.fromMap((d as Map).cast<String, dynamic>());
    } on ApiException catch (e) {
      if (e.statut == 403 || e.statut == 404) return null;
      throw mapError('ProfileRepository.fetchCitoyen', e);
    } catch (e, st) {
      throw mapError('ProfileRepository.fetchCitoyen', e, st);
    }
  }

  Future<void> updateCitoyen(Citoyen citoyen) async {
    try {
      final m = citoyen.toUpdateMap();
      await _api.patch('moi/citoyen', {
        'nom': m['nom'] ?? '',
        'prenom': m['prenom'] ?? '',
        // Le serveur attend une chaîne, vide si aucun email.
        'email': m['email'] ?? '',
      });
    } catch (e, st) {
      throw mapError('ProfileRepository.updateCitoyen', e, st);
    }
  }

  /// Photo du profil (citoyen), photo professionnelle (prestataire) ou logo
  /// (entreprise), selon le compte connecté ; renvoie son adresse.
  Future<String?> envoyerPhotoProfil(File photo) async {
    try {
      final profil = await _api.envoyerFichiers('moi/photo', fichiers: {'fichier': photo})
          as Map;
      return (profil['photo_url'] ?? profil['logo_url']) as String?;
    } catch (e, st) {
      throw mapError('ProfileRepository.envoyerPhotoProfil', e, st);
    }
  }

  // --- Particulier (prestataire indépendant) ---

  Future<void> createParticulier({
    required String id,
    required String telephone,
    String nom = '',
    String prenom = '',
    List<String> services = const [],
    String? photoProUrl,
  }) =>
      createProfileEntry(id, 'particulier');

  Future<Particulier?> fetchParticulier(String id) async {
    try {
      return Particulier.fromMap(versParticulier(await _api.get('moi/prestataire')));
    } on ApiException catch (e) {
      if (e.statut == 403 || e.statut == 404) return null;
      throw mapError('ProfileRepository.fetchParticulier', e);
    } catch (e, st) {
      throw mapError('ProfileRepository.fetchParticulier', e, st);
    }
  }

  /// Le téléphone est l'identifiant de connexion : il ne se change pas.
  Future<void> updateParticulierInfo({
    required String id,
    required String nom,
    required String telephone,
    String? prenom,
    List<String>? services,
  }) async {
    try {
      await _api.patch('moi/prestataire', {
        'nom': nom,
        if (prenom != null) 'prenom': prenom,
        if (services != null) 'services': services,
      });
    } catch (e, st) {
      throw mapError('ProfileRepository.updateParticulierInfo', e, st);
    }
  }

  /// Essai gratuit (une seule fois) ; sa durée est fixée par le serveur.
  Future<void> startFreeTrial(String id, {required Duration duration}) async {
    try {
      await _api.post('moi/prestataire/essai');
    } catch (e, st) {
      throw mapError('ProfileRepository.startFreeTrial', e, st);
    }
  }

  // --- Entreprise ---

  Future<void> createEntreprise({
    required String id,
    required String nomEntreprise,
    required String secteurActivite,
    required String telephone,
    String? logoUrl,
  }) async {
    try {
      await _api.put('moi/entreprise', {
        'nom_entreprise': nomEntreprise,
        'secteur_activite': secteurActivite,
      });
      await _api.session.majType('entreprise');
    } catch (e, st) {
      throw mapError('ProfileRepository.createEntreprise', e, st);
    }
  }

  Future<Entreprise?> fetchEntreprise(String id) async {
    try {
      final d = await _api.get('moi/entreprise');
      return Entreprise.fromMap((d as Map).cast<String, dynamic>());
    } on ApiException catch (e) {
      if (e.statut == 403 || e.statut == 404) return null;
      throw mapError('ProfileRepository.fetchEntreprise', e);
    } catch (e, st) {
      throw mapError('ProfileRepository.fetchEntreprise', e, st);
    }
  }

  Future<void> updateEntreprise({
    required String id,
    required String nomEntreprise,
    required String telephone,
  }) async {
    try {
      await _api.patch('moi/entreprise', {'nom_entreprise': nomEntreprise});
    } catch (e, st) {
      throw mapError('ProfileRepository.updateEntreprise', e, st);
    }
  }

  /// Retire l'entreprise de la plateforme (ses signalements restent).
  Future<void> deleteEntreprise(String id) async {
    try {
      await _api.delete('moi/entreprise');
    } catch (e, st) {
      throw mapError('ProfileRepository.deleteEntreprise', e, st);
    }
  }
}
