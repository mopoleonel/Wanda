import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/avis_repository.dart';
import '../../data/repositories/demande_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/prestataire_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/signalement_repository.dart';
import '../../data/repositories/sollicitation_repository.dart';
import '../../data/repositories/verification_repository.dart';
import '../api/api_client.dart';
import '../api/session.dart';
import '../notifications/push_notification_service.dart';

/// Session de connexion, chargée au démarrage (voir main.dart) ; remplacée
/// par une session en mémoire dans les tests.
final gestionSessionProvider = Provider<GestionSession>((ref) {
  return GestionSession(StockageSessionMemoire());
});

/// Client de l'API WANDA, partagé par tous les dépôts.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(session: ref.watch(gestionSessionProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider));
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(apiClientProvider));
});

final prestataireRepositoryProvider = Provider<PrestataireRepository>((ref) {
  return PrestataireRepository(ref.watch(apiClientProvider));
});

final sollicitationRepositoryProvider = Provider<SollicitationRepository>((ref) {
  return SollicitationRepository(ref.watch(apiClientProvider));
});

final signalementRepositoryProvider = Provider<SignalementRepository>((ref) {
  return SignalementRepository(ref.watch(apiClientProvider));
});

final avisRepositoryProvider = Provider<AvisRepository>((ref) {
  return AvisRepository(ref.watch(apiClientProvider));
});

final verificationRepositoryProvider = Provider<VerificationRepository>((ref) {
  return VerificationRepository(ref.watch(apiClientProvider));
});

final demandeRepositoryProvider = Provider<DemandeRepository>((ref) {
  return DemandeRepository(ref.watch(apiClientProvider));
});

final tarifRepositoryProvider = Provider<TarifRepository>((ref) {
  return TarifRepository(ref.watch(apiClientProvider));
});

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(apiClientProvider));
});

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  return PushNotificationService(ref.watch(notificationRepositoryProvider));
});

/// Émet à chaque connexion ou déconnexion (session expirée comprise).
final sessionChangesProvider = StreamProvider<Session?>((ref) {
  return ref.watch(gestionSessionProvider).changements;
});
