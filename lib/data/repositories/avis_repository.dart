import '../../core/api/api_client.dart';
import '../../core/error/error_mapper.dart';
import '../models/avis_prestataire.dart';

/// Avis des clients sur les prestataires, et notes moyennes.
class AvisRepository {
  final ApiClient _api;
  AvisRepository(this._api);

  /// Note d'une mission terminée (une seule par mission, vérifié par le
  /// serveur).
  Future<void> create({
    required String sollicitationId,
    required String prestataireId,
    required String citoyenId,
    required int note,
    String? commentaire,
  }) async {
    try {
      await _api.post('demandes/$sollicitationId/avis', {
        'note': note,
        'commentaire': commentaire ?? '',
      });
    } catch (e, st) {
      throw mapError('AvisRepository.create', e, st);
    }
  }

  Future<RatingSummary> averageForPrestataire(String prestataireId) async {
    final summaries = await averagesForPrestataires([prestataireId]);
    return summaries[prestataireId] ?? RatingSummary.empty;
  }

  /// Moyennes de plusieurs prestataires en une seule requête.
  Future<Map<String, RatingSummary>> averagesForPrestataires(
      List<String> prestataireIds) async {
    if (prestataireIds.isEmpty) return {};
    try {
      final d = await _api.get('notes', query: {'ids': prestataireIds.join(',')}) as Map;
      return {
        for (final e in d.entries)
          '${e.key}': RatingSummary(
            average: ((e.value as Map)['moyenne'] as num).toDouble(),
            count: ((e.value as Map)['nombre'] as num).toInt(),
          ),
      };
    } catch (e, st) {
      throw mapError('AvisRepository.averagesForPrestataires', e, st);
    }
  }
}

/// Regroupe des lignes brutes `{prestataire_id, note}` en moyenne par
/// prestataire (fonction pure, gardée pour les calculs locaux et les tests).
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
