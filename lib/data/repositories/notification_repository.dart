import '../../core/api/api_client.dart';
import '../../core/error/error_mapper.dart';

/// Appareils inscrits aux notifications push (jetons Firebase).
class NotificationRepository {
  final ApiClient _api;
  NotificationRepository(this._api);

  /// Le jeton est rattaché au compte connecté (côté serveur).
  Future<void> registerToken({
    required String userId,
    required String fcmToken,
    String platform = 'android',
  }) async {
    try {
      await _api.post('moi/appareils', {'fcm_token': fcmToken, 'plateforme': platform});
    } catch (e, st) {
      throw mapError('NotificationRepository.registerToken', e, st);
    }
  }

  Future<void> unregisterToken(String fcmToken) async {
    try {
      await _api.delete('moi/appareils/${Uri.encodeComponent(fcmToken)}');
    } catch (e, st) {
      throw mapError('NotificationRepository.unregisterToken', e, st);
    }
  }
}
