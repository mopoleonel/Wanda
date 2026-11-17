import '../../core/api/api_client.dart';
import '../../core/api/sondage.dart';
import '../../core/error/error_mapper.dart';
import '../api/adaptateurs.dart';
import '../models/sollicitation.dart';

/// Cycle de vie d'une demande : en_attente -> accepte -> termine -> archive,
/// ou refuse / annule. Chaque transition est vérifiée par le serveur (qui
/// agit, et à quel moment).
class SollicitationRepository {
  final ApiClient _api;
  SollicitationRepository(this._api);

  static const _actions = {
    'accepte': 'accepter',
    'refuse': 'refuser',
    'termine': 'terminer',
    'annule': 'annuler',
    'archive': 'classer',
  };

  /// Demandes du client connecté (50 plus récentes), suivies en direct.
  Stream<List<Sollicitation>> streamForCitoyen(String citoyenId) => sonder(
        () => _api.get('demandes', query: {'role': 'citoyen'}),
        intervalle: const Duration(seconds: 6),
      ).map((d) =>
          [for (final s in liste(d)) Sollicitation.fromMap(versSollicitation(s))]);

  /// Signal : une mission du prestataire a été créée ou modifiée (nouvelle
  /// demande, annulation, ajustement accepté…). L'écran relit alors la
  /// liste avec [fetchForPrestataire].
  Stream<void> changementsPrestataire(String prestataireId) => sonder(
        () => _api.get('demandes', query: {'role': 'prestataire'}),
        intervalle: const Duration(seconds: 8),
        // Seules la liste et les dates de modification comptent.
        empreinte: (d) => [for (final s in liste(d)) [s['id'], s['modifie_le']]],
      ).map((_) {});

  /// Missions reçues par le prestataire connecté.
  Future<List<Sollicitation>> fetchForPrestataire(
    String prestataireId, {
    int page = 0,
    int pageSize = 30,
  }) async {
    try {
      final d = await _api.get('demandes',
          query: {'role': 'prestataire', 'page': '${page + 1}'});
      return [for (final s in liste(d)) Sollicitation.fromMap(versSollicitation(s))];
    } on ApiException catch (e) {
      // Au-delà de la dernière page : plus rien.
      if (e.statut == 404) return const [];
      throw mapError('SollicitationRepository.fetchForPrestataire', e);
    } catch (e, st) {
      throw mapError('SollicitationRepository.fetchForPrestataire', e, st);
    }
  }

  /// Change le statut. [dateFin] est fixée par le serveur (fin de mission).
  Future<void> updateStatus(String id, String status, {DateTime? dateFin}) async {
    final action = _actions[status];
    try {
      if (action == null) throw ArgumentError.value(status, 'status');
      await _api.post('demandes/$id/$action');
    } catch (e, st) {
      throw mapError('SollicitationRepository.updateStatus', e, st);
    }
  }

  Future<void> archive(String id) => updateStatus(id, 'archive');
  Future<void> cancel(String id) => updateStatus(id, 'annule');
}
