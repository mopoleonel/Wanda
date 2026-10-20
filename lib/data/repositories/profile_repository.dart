import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/error_mapper.dart';
import '../models/citoyen.dart';
import '../models/entreprise.dart';
import '../models/particulier.dart';

/// Lecture/écriture des profils métier (citoyens, particuliers, entreprises)
/// et de la table de référence `profiles`.
class ProfileRepository {
  final SupabaseClient _client;
  ProfileRepository(this._client);

  Future<void> createProfileEntry(String userId, String userType) async {
    try {
      await _client.from('profiles').insert({
        'id': userId,
        'user_type': userType,
      });
    } catch (e, st) {
      throw mapError('ProfileRepository.createProfileEntry', e, st);
    }
  }

  // --- Citoyen ---

  /// Seul le téléphone (WhatsApp vérifié) est obligatoire à l'inscription :
  /// nom, prénom et email se complètent ensuite depuis le profil.
  Future<void> createCitoyen({
    required String citoyenId,
    required String telephone,
    String? nom,
    String? prenom,
    String? email,
  }) async {
    try {
      await _client.from('citoyens').insert({
        'citoyen_id': citoyenId,
        'telephone': telephone,
        if (nom != null && nom.isNotEmpty) 'nom': nom,
        if (prenom != null && prenom.isNotEmpty) 'prenom': prenom,
        if (email != null && email.isNotEmpty) 'email': email,
      });
    } catch (e, st) {
      throw mapError('ProfileRepository.createCitoyen', e, st);
    }
  }

  Future<Citoyen?> fetchCitoyen(String citoyenId) async {
    try {
      final data = await _client
          .from('citoyens')
          .select()
          .eq('citoyen_id', citoyenId)
          .maybeSingle();
      return data == null ? null : Citoyen.fromMap(data);
    } catch (e, st) {
      throw mapError('ProfileRepository.fetchCitoyen', e, st);
    }
  }

  Future<void> updateCitoyen(Citoyen citoyen) async {
    try {
      await _client
          .from('citoyens')
          .update(citoyen.toUpdateMap())
          .eq('citoyen_id', citoyen.citoyenId);
    } catch (e, st) {
      throw mapError('ProfileRepository.updateCitoyen', e, st);
    }
  }

  Future<void> updateCitoyenPhoto(String citoyenId, String photoUrl) async {
    try {
      await _client
          .from('citoyens')
          .update({'photo_url': photoUrl}).eq('citoyen_id', citoyenId);
    } catch (e, st) {
      throw mapError('ProfileRepository.updateCitoyenPhoto', e, st);
    }
  }

  // --- Particulier (prestataire indépendant) ---

  /// Crée la fiche artisan. À l'inscription seul le numéro vérifié est
  /// connu : nom, prénom, métier et photo sont complétés depuis l'espace
  /// artisan (chaînes vides = « à compléter », voir `Particulier.profilManquant`).
  Future<void> createParticulier({
    required String id,
    required String telephone,
    String nom = '',
    String prenom = '',
    String servicePropose = '',
    String? photoProUrl,
  }) async {
    try {
      await _client.from('particuliers').insert({
        'id': id,
        'nom': nom,
        'prenom': prenom,
        'service_propose': servicePropose,
        'telephone': telephone,
        'photo_pro_url': photoProUrl ?? '',
      });
    } catch (e, st) {
      throw mapError('ProfileRepository.createParticulier', e, st);
    }
  }

  /// `true` si un autre compte prestataire (artisan ou entreprise) utilise
  /// déjà ce numéro : typiquement un ancien compte « numéro + mot de passe »,
  /// distinct du compte créé par le code WhatsApp.
  Future<bool> isPhoneUsedByOtherPrestataire(
      String phone, String exceptUserId) async {
    try {
      for (final table in const ['particuliers', 'entreprises']) {
        final rows = await _client
            .from(table)
            .select('id')
            .eq('telephone', phone)
            .neq('id', exceptUserId)
            .limit(1);
        if (rows.isNotEmpty) return true;
      }
      return false;
    } catch (e, st) {
      throw mapError('ProfileRepository.isPhoneUsedByOtherPrestataire', e, st);
    }
  }

  Future<Particulier?> fetchParticulier(String id) async {
    try {
      final data = await _client
          .from('particuliers')
          .select()
          .eq('id', id)
          .maybeSingle();
      return data == null ? null : Particulier.fromMap(data);
    } catch (e, st) {
      throw mapError('ProfileRepository.fetchParticulier', e, st);
    }
  }

  Future<void> updateParticulierInfo({
    required String id,
    required String nom,
    required String telephone,
    String? prenom,
    String? servicePropose,
  }) async {
    try {
      await _client.from('particuliers').update({
        'nom': nom,
        'telephone': telephone,
        if (prenom != null) 'prenom': prenom,
        if (servicePropose != null) 'service_propose': servicePropose,
      }).eq('id', id);
    } catch (e, st) {
      throw mapError('ProfileRepository.updateParticulierInfo', e, st);
    }
  }

  Future<void> updateParticulierPhoto(String id, String photoUrl) async {
    try {
      await _client
          .from('particuliers')
          .update({'photo_pro_url': photoUrl}).eq('id', id);
    } catch (e, st) {
      throw mapError('ProfileRepository.updateParticulierPhoto', e, st);
    }
  }

  Future<void> startFreeTrial(String id, {required Duration duration}) async {
    try {
      final expiry = DateTime.now().add(duration);
      await _client.from('particuliers').update({
        'essai_utilise': true,
        'type_abonnement': 'ESSAI',
        'abonnement_expire_at': expiry.toIso8601String(),
      }).eq('id', id);
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
      await _client.from('entreprises').insert({
        'id': id,
        'nom_entreprise': nomEntreprise,
        'secteur_activite': secteurActivite,
        'telephone': telephone,
        'logo_url': logoUrl ?? '',
      });
    } catch (e, st) {
      throw mapError('ProfileRepository.createEntreprise', e, st);
    }
  }

  Future<Entreprise?> fetchEntreprise(String id) async {
    try {
      final data =
          await _client.from('entreprises').select().eq('id', id).maybeSingle();
      return data == null ? null : Entreprise.fromMap(data);
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
      await _client.from('entreprises').update({
        'nom_entreprise': nomEntreprise,
        'telephone': telephone,
      }).eq('id', id);
    } catch (e, st) {
      throw mapError('ProfileRepository.updateEntreprise', e, st);
    }
  }

  Future<void> updateEntrepriseLogo(String id, String logoUrl) async {
    try {
      await _client
          .from('entreprises')
          .update({'logo_url': logoUrl}).eq('id', id);
    } catch (e, st) {
      throw mapError('ProfileRepository.updateEntrepriseLogo', e, st);
    }
  }

  /// Retire l'entreprise de la plateforme (la ligne métier seulement : le
  /// compte Auth ne peut être supprimé que côté serveur, clé service_role).
  Future<void> deleteEntreprise(String id) async {
    try {
      await _client.from('entreprises').delete().eq('id', id);
    } catch (e, st) {
      throw mapError('ProfileRepository.deleteEntreprise', e, st);
    }
  }
}
