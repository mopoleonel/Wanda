import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../data/repositories/notification_repository.dart';
import '../error/app_logger.dart';

/// Intégration Firebase Cloud Messaging.
///
/// IMPORTANT — état actuel : ce service n'est PAS encore actif. Pour
/// l'activer une fois le projet Firebase créé :
///   1. Placer `android/app/google-services.json` (et `ios/Runner/GoogleService-Info.plist`)
///   2. Appliquer le plugin Gradle `com.google.gms.google-services` dans
///      android/app/build.gradle et android/build.gradle
///   3. Appeler `PushNotificationService.initializeFirebase()` tout en haut
///      de `main()`, avant `runApp(...)`
///
/// [registerDeviceForUser] est déjà appelé après connexion réussie
/// (citoyen et prestataire) — il échoue silencieusement tant que Firebase
/// n'est pas initialisé, donc rien d'autre à faire côté code après ces
/// trois étapes.
class PushNotificationService {
  final NotificationRepository _repository;
  PushNotificationService(this._repository);

  static Future<void> initializeFirebase() async {
    await Firebase.initializeApp();
  }

  Future<void> registerDeviceForUser(String userId) async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await messaging.getToken();
      if (token != null) {
        await _repository.registerToken(userId: userId, fcmToken: token);
      }

      messaging.onTokenRefresh.listen((newToken) {
        _repository
            .registerToken(userId: userId, fcmToken: newToken)
            .catchError(
                (e) => AppLogger.error('PushNotification.onTokenRefresh', e));
      });
    } catch (e, st) {
      // Firebase non configuré, ou permission refusée : non bloquant, l'app
      // fonctionne simplement sans notifications push.
      AppLogger.error('PushNotificationService.registerDeviceForUser', e, st);
    }
  }
}
