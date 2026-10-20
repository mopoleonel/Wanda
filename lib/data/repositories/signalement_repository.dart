import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/error_mapper.dart';
import '../models/signalement.dart';

/// Création des signalements citoyens (attribués à l'entreprise du
/// secteur) et lecture / avancement côté entreprise.
class SignalementRepository {
  final SupabaseClient _client;
  SignalementRepository(this._client);

  /// Entreprise qui traite [secteur] (voir `secteurPourType`), s'il y en a
  /// une : le signalement lui est alors attribué dès l'envoi.
  Future<String?> findEntrepriseIdForSecteur(String secteur) async {
    try {
      final data = await _client
          .from('entreprises')
          .select('id')
          .eq('secteur_activite', secteur)
          .limit(1)
          .maybeSingle();
      return data?['id'] as String?;
    } catch (e, st) {
      throw mapError('SignalementRepository.findEntrepriseIdForSecteur', e, st);
    }
  }

  Future<void> create({
    required String typeProbleme,
    required String imageUrl,
    required double latitude,
    required double longitude,
    String? entrepriseId,
    required String citoyenId,
    String? iaValidationDetails,
  }) async {
    try {
      await _client.from('signalements').insert({
        'type_probleme': typeProbleme,
        'image_url': imageUrl,
        'latitude': latitude,
        'longitude': longitude,
        'entreprise_id': entrepriseId,
        'citoyen_id': citoyenId,
        'statut': 'en_attente',
        'ia_validation_details': iaValidationDetails,
      });
    } catch (e, st) {
      throw mapError('SignalementRepository.create', e, st);
    }
  }

  /// Missions d'une entreprise : les signalements qui lui sont attribués,
  /// plus ceux des [types] de son secteur (anciens signalements enregistrés
  /// sans entreprise), du plus récent au plus ancien.
  Future<List<Signalement>> fetchForEntreprise(
    String entrepriseId,
    List<String> types, {
    int pageSize = 100,
  }) async {
    try {
      final inList = types.map((t) => '"${t.replaceAll('"', '')}"').join(',');
      final rows = await _client
          .from('signalements')
          .select()
          .or('entreprise_id.eq.$entrepriseId,type_probleme.in.($inList)')
          .order('created_at', ascending: false)
          .limit(pageSize);
      return (rows as List)
          .map((r) => Signalement.fromMap(Map<String, dynamic>.from(r)))
          .toList();
    } catch (e, st) {
      throw mapError('SignalementRepository.fetchForEntreprise', e, st);
    }
  }

  /// Avancement d'une mission : en_cours, resolu ou rejete.
  Future<void> updateStatut(String id, String statut) async {
    try {
      await _client
          .from('signalements')
          .update({'statut': statut}).eq('id', id);
    } catch (e, st) {
      throw mapError('SignalementRepository.updateStatut', e, st);
    }
  }
}
