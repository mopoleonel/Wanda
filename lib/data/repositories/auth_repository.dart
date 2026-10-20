import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_exception.dart';
import '../../core/error/error_mapper.dart';

/// Types de compte gérés par l'app. Reflète la colonne `profiles.user_type`.
enum UserType { citoyen, particulier, entreprise }

UserType? userTypeFromString(String? value) {
  switch (value) {
    case 'citoyen':
      return UserType.citoyen;
    case 'particulier':
      return UserType.particulier;
    case 'entreprise':
      return UserType.entreprise;
    default:
      return null;
  }
}

/// Authentification Supabase + résolution du type de compte
/// (`profiles.user_type`). Toute la logique d'auth passait auparavant
/// directement par `Supabase.instance.client` dans chaque écran.
class AuthRepository {
  final SupabaseClient _client;
  AuthRepository(this._client);

  String? get currentUserId => _client.auth.currentUser?.id;

  /// `true` si la session a été ouverte par un numéro vérifié (WhatsApp).
  bool get hasVerifiedPhone =>
      (_client.auth.currentUser?.phone ?? '').isNotEmpty;

  /// Envoie un code à usage unique sur WhatsApp. Crée le compte Supabase Auth
  /// s'il n'existe pas encore : inscription et connexion sont le même flux.
  /// [phone] doit être au format E.164 (voir `normalizePhone`).
  Future<void> sendWhatsAppOtp(String phone) async {
    try {
      await _client.auth.signInWithOtp(
        phone: phone,
        channel: OtpChannel.whatsapp,
      );
    } catch (e, st) {
      throw mapError('AuthRepository.sendWhatsAppOtp', e, st);
    }
  }

  /// Vérifie le code reçu sur WhatsApp et ouvre la session.
  /// Retourne l'id de l'utilisateur connecté.
  Future<String> verifyWhatsAppOtp({
    required String phone,
    required String code,
  }) async {
    try {
      final res = await _client.auth.verifyOTP(
        phone: phone,
        token: code.trim(),
        type: OtpType.sms,
      );
      final userId = res.user?.id;
      if (userId == null) {
        throw const AppException('Code invalide ou expiré.');
      }
      return userId;
    } catch (e, st) {
      throw mapError('AuthRepository.verifyWhatsAppOtp', e, st);
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e, st) {
      throw mapError('AuthRepository.signOut', e, st);
    }
  }

  Future<UserType?> fetchUserType(String userId) async {
    try {
      final profile = await _client
          .from('profiles')
          .select('user_type')
          .eq('id', userId)
          .maybeSingle();
      return userTypeFromString(profile?['user_type'] as String?);
    } catch (e, st) {
      throw mapError('AuthRepository.fetchUserType', e, st);
    }
  }
}
