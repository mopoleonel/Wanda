import 'package:flutter/foundation.dart';

/// Point d'entrée unique pour le logging d'erreurs côté client.
///
/// Aujourd'hui ça ne fait qu'un `debugPrint`, mais toute intégration future
/// d'un service de crash reporting (Sentry, Firebase Crashlytics...) se
/// branche ici, sans toucher au reste du code.
class AppLogger {
  AppLogger._();

  static void error(String context, Object error, [StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('[$context] $error');
      if (stackTrace != null) debugPrint(stackTrace.toString());
    }
  }
}
