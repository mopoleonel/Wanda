import '../../core/api/api_client.dart';
import '../../core/api/sondage.dart';
import '../../core/error/error_mapper.dart';
import '../api/adaptateurs.dart';
import '../models/particulier.dart';

/// Prestataires en ligne (côté client) et disponibilité du prestataire
/// connecté.
class PrestataireRepository {
  final ApiClient _api;
  PrestataireRepository(this._api);

  /// Prestataires réservables (en ligne, abonnés, avec au moins un
  /// service), relus régulièrement. Le filtre par service se fait dans
  /// l'écran.
  Stream<List<Particulier>> streamAvailable() =>
      sonder(() => _api.get('prestataires'), intervalle: const Duration(seconds: 20))
          .map((d) => [for (final p in liste(d)) Particulier.fromMap(versParticulier(p))]);

  /// Prestataires en ligne qui proposent [serviceCode].
  Future<List<Particulier>> disponiblesPour(String serviceCode) async {
    try {
      final d = await _api.get('prestataires', query: {'service': serviceCode});
      return [for (final p in liste(d)) Particulier.fromMap(versParticulier(p))];
    } catch (e, st) {
      throw mapError('PrestataireRepository.disponiblesPour', e, st);
    }
  }

  Future<Particulier?> getById(String id) async {
    try {
      return Particulier.fromMap(versParticulier(await _api.get('prestataires/$id')));
    } on ApiException catch (e) {
      if (e.statut == 404) return null;
      throw mapError('PrestataireRepository.getById', e);
    } catch (e, st) {
      throw mapError('PrestataireRepository.getById', e, st);
    }
  }

  /// En ligne / hors ligne. En ligne, la position permet aux clients de
  /// trier par proximité ; le serveur exige un abonnement valide.
  Future<void> setAvailability(
    String id,
    bool isAvailable, {
    double? latitude,
    double? longitude,
  }) async {
    try {
      await _api.post('moi/prestataire/en-ligne', {
        'en_ligne': isAvailable,
        if (isAvailable && latitude != null && longitude != null) ...{
          'latitude': latitude,
          'longitude': longitude,
        },
      });
    } catch (e, st) {
      throw mapError('PrestataireRepository.setAvailability', e, st);
    }
  }
}
