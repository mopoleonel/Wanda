import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/error_mapper.dart';
import '../models/sollicitation.dart';

/// Cycle de vie d'une "sollicitation" (demande de mission d'un citoyen vers
/// un prestataire) : en_attente -> accepte -> termine / annule -> archive.
class SollicitationRepository {
  final SupabaseClient _client;
  SollicitationRepository(this._client);

  Future<void> create({
    required String prestataireId,
    required String citoyenId,
    required String nomCitoyen,
    required String prenomCitoyen,
    required String numeroCitoyen,
  }) async {
    try {
      await _client.from('sollicitations').insert({
        'prestataire_id': prestataireId,
        'citoyen_id': citoyenId,
        'nom_citoyen': nomCitoyen,
        'prenom_citoyen': prenomCitoyen,
        'numero_citoyen': numeroCitoyen,
        'date_sollicitation': DateTime.now().toUtc().toIso8601String(),
        'statut': 'en_attente',
      }).timeout(const Duration(seconds: 15));
    } catch (e, st) {
      throw mapError('SollicitationRepository.create', e, st);
    }
  }

  /// Suivi temps réel des sollicitations d'un citoyen, avec les infos de
  /// l'expert associé. Limité aux 50 plus récentes pour éviter de charger un
  /// historique complet sur un flux réactif.
  Stream<List<Sollicitation>> streamForCitoyen(String citoyenId) {
    return _client
        .from('sollicitations')
        .stream(primaryKey: ['id'])
        .eq('citoyen_id', citoyenId)
        .order('date_sollicitation', ascending: false)
        .limit(50)
        .asyncMap((rows) async {
          final result = <Sollicitation>[];
          for (final row in rows) {
            final map = Map<String, dynamic>.from(row);
            try {
              final expertData = await _client
                  .from('particuliers')
                  .select('nom, prenom, telephone, services, photo_pro_url')
                  .eq('id', row['prestataire_id'])
                  .single();
              map['expert'] = expertData;
            } catch (_) {
              map['expert'] = null;
            }
            result.add(Sollicitation.fromMap(map));
          }
          return result;
        });
  }

  /// Signal temps réel : une mission du prestataire a été créée ou modifiée
  /// (nouvelle demande, annulation, prix ajusté…). L'écran relit ensuite la
  /// liste paginée avec [fetchForPrestataire].
  Stream<void> changementsPrestataire(String prestataireId) => _client
      .from('sollicitations')
      .stream(primaryKey: ['id'])
      .eq('prestataire_id', prestataireId)
      .map((_) {});

  /// Missions reçues par un prestataire, paginées.
  Future<List<Sollicitation>> fetchForPrestataire(
    String prestataireId, {
    int page = 0,
    int pageSize = 30,
  }) async {
    try {
      final from = page * pageSize;
      final to = from + pageSize - 1;
      final rows = await _client
          .from('sollicitations')
          .select('*')
          .eq('prestataire_id', prestataireId)
          .order('date_sollicitation', ascending: false)
          .range(from, to)
          .timeout(const Duration(seconds: 10));
      return (rows as List)
          .map((r) => Sollicitation.fromMap(Map<String, dynamic>.from(r)))
          .toList();
    } catch (e, st) {
      throw mapError('SollicitationRepository.fetchForPrestataire', e, st);
    }
  }

  Future<void> updateStatus(String id, String status,
      {DateTime? dateFin}) async {
    try {
      final update = <String, dynamic>{'statut': status};
      if (dateFin != null) {
        update['date_fin'] = dateFin.toUtc().toIso8601String();
      }
      await _client.from('sollicitations').update(update).eq('id', id);
    } catch (e, st) {
      throw mapError('SollicitationRepository.updateStatus', e, st);
    }
  }

  Future<void> archive(String id) => updateStatus(id, 'archive');
  Future<void> cancel(String id) => updateStatus(id, 'annule');
}
