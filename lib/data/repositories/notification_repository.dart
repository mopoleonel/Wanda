import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/error_mapper.dart';

/// Tokens FCM enregistrés pour les notifications push (voir
/// supabase/sql/002_device_tokens.sql).
class NotificationRepository {
  final SupabaseClient _client;
  NotificationRepository(this._client);

  Future<void> registerToken({
    required String userId,
    required String fcmToken,
    String platform = 'android',
  }) async {
    try {
      await _client.from('device_tokens').upsert(
        {
          'user_id': userId,
          'fcm_token': fcmToken,
          'platform': platform,
        },
        onConflict: 'fcm_token',
      );
    } catch (e, st) {
      throw mapError('NotificationRepository.registerToken', e, st);
    }
  }

  Future<void> unregisterToken(String fcmToken) async {
    try {
      await _client.from('device_tokens').delete().eq('fcm_token', fcmToken);
    } catch (e, st) {
      throw mapError('NotificationRepository.unregisterToken', e, st);
    }
  }
}
