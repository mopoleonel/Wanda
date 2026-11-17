import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api/session.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/providers/repository_providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  await PushNotificationService.initializeFirebase();

  // Session du dernier lancement (jetons de l'API WANDA, stockage chiffré).
  // L'adresse de l'API est fixée à la compilation (--dart-define=API_URL).
  final session = GestionSession(StockageSessionSecurise());
  await session.charger();

  runApp(ProviderScope(
    overrides: [gestionSessionProvider.overrideWithValue(session)],
    child: const MyApp(),
  ));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'WANDA',
      // Thème clair imposé : l'app s'utilise surtout dehors, en plein soleil.
      themeMode: ThemeMode.light,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
