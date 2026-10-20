import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/error_mapper.dart';
import '../models/avis_prestataire.dart';

/// Avis citoyens sur les prestataires, et agrégation en note moyenne.
///
/// C'est ici que se corrige le bug trouvé lors de l'audit : la note "5.0"
/// était codée en dur dans l'UI alors que les vrais avis étaient bien
/// enregistrés en base sans jamais être lus.
class AvisRepository {
  final SupabaseClient _client;
  AvisRepository(this._client);

  Future<void> create({
    required String sollicitationId,
    required String prestataireId,
    required String citoyenId,
    required int note,
    String? commentaire,
  }) async {
    try {
      await _client.from('avis_prestataires').insert({
        'sollicitation_id': sollicitationId,
        'prestataire_id': prestataireId,
        'citoyen_id': citoyenId,
        'note': note,
        'commentaire': commentaire,
      });
    } catch (e, st) {
      throw mapError('AvisRepository.create', e, st);
    }
  }

  Future<RatingSummary> averageForPrestataire(String prestataireId) async {
    final summaries = await averagesForPrestataires([prestataireId]);
    return summaries[prestataireId] ?? RatingSummary.empty;
  }

  /// Récupère les moyennes de plusieurs prestataires en une seule requête,
  /// pour éviter le problème N+1 quand on affiche une liste d'experts.
  Future<Map<String, RatingSummary>> averagesForPrestataires(
      List<String> prestataireIds) async {
    if (prestataireIds.isEmpty) return {};
    try {
      final rows = await _client
          .from('avis_prestataires')
          .select('prestataire_id, note')
          .inFilter('prestataire_id', prestataireIds);
      return aggregateRatings(List<Map<String, dynamic>>.from(rows as List));
    } catch (e, st) {
      throw mapError('AvisRepository.averagesForPrestataires', e, st);
    }
  }
}

/// Regroupe des lignes brutes `{prestataire_id, note}` en moyenne par
/// prestataire. Extrait en fonction pure (testable sans mocker Supabase).
Map<String, RatingSummary> aggregateRatings(List<Map<String, dynamic>> rows) {
  final byPrestataire = <String, List<int>>{};
  for (final row in rows) {
    final id = row['prestataire_id'] as String;
    final note = (row['note'] as num).toInt();
    byPrestataire.putIfAbsent(id, () => []).add(note);
  }

  return byPrestataire.map((id, notes) {
    final avg = notes.reduce((a, b) => a + b) / notes.length;
    return MapEntry(id, RatingSummary(average: avg, count: notes.length));
  });
}
