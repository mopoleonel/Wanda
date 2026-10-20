import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/avis_repository.dart';
import '../../data/repositories/demande_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/prestataire_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/signalement_repository.dart';
import '../../data/repositories/sollicitation_repository.dart';
import '../../data/repositories/storage_repository.dart';
import '../../data/repositories/verification_repository.dart';
import '../notifications/push_notification_service.dart';

/// Client Supabase partagé. Toujours accédé via ce provider plutôt que
/// `Supabase.instance.client` directement, pour rester testable (on peut
/// override ce provider dans les tests).
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(supabaseClientProvider));
});

final prestataireRepositoryProvider = Provider<PrestataireRepository>((ref) {
  return PrestataireRepository(ref.watch(supabaseClientProvider));
});

final sollicitationRepositoryProvider =
    Provider<SollicitationRepository>((ref) {
  return SollicitationRepository(ref.watch(supabaseClientProvider));
});

final signalementRepositoryProvider = Provider<SignalementRepository>((ref) {
  return SignalementRepository(ref.watch(supabaseClientProvider));
});

final avisRepositoryProvider = Provider<AvisRepository>((ref) {
  return AvisRepository(ref.watch(supabaseClientProvider));
});

final storageRepositoryProvider = Provider<StorageRepository>((ref) {
  return StorageRepository(ref.watch(supabaseClientProvider));
});

final verificationRepositoryProvider = Provider<VerificationRepository>((ref) {
  return VerificationRepository(ref.watch(supabaseClientProvider));
});

final demandeRepositoryProvider = Provider<DemandeRepository>((ref) {
  return DemandeRepository(ref.watch(supabaseClientProvider));
});

final tarifRepositoryProvider = Provider<TarifRepository>((ref) {
  return TarifRepository(ref.watch(supabaseClientProvider));
});

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(supabaseClientProvider));
});

final pushNotificationServiceProvider =
    Provider<PushNotificationService>((ref) {
  return PushNotificationService(ref.watch(notificationRepositoryProvider));
});

/// Émet à chaque changement d'état d'authentification Supabase (connexion,
/// déconnexion, refresh de session) — utilisé par le router pour les
/// redirections automatiques.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});
