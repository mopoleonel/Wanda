import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/citoyen_login_page.dart';
import '../../features/auth/presta_login_page.dart';
import '../../features/certification/certification_page.dart';
import '../../features/dashboard_entreprise/dashboard_entreprise_page.dart';
import '../../features/dashboard_particulier/dashboard_particulier_page.dart';
import '../../features/home/home_page.dart';
import '../../features/services/service_page.dart';
import '../../features/signalement/signal_page.dart';
import '../../features/splash/splash_screen.dart';
import 'app_routes.dart';

/// Transition partagée par toutes les routes : fondu + léger glissement
/// vertical, plus sobre et cohérent que le slide horizontal Material par
/// défaut — utilisée systématiquement pour que chaque navigation se
/// ressente de la même façon dans toute l'app.
CustomTransitionPage<void> _fadeThrough(Widget child, GoRouterState state) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.03), end: Offset.zero)
              .animate(curved),
          child: child,
        ),
      );
    },
  );
}

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        pageBuilder: (context, state) =>
            _fadeThrough(const SplashScreen(), state),
      ),
      GoRoute(
        path: AppRoutes.home,
        pageBuilder: (context, state) => _fadeThrough(const HomePage(), state),
      ),
      GoRoute(
        path: AppRoutes.citoyenLogin,
        pageBuilder: (context, state) =>
            _fadeThrough(const LoginCitoyenPage(), state),
      ),
      GoRoute(
        path: AppRoutes.citoyenServices,
        pageBuilder: (context, state) => _fadeThrough(
            ServicePage(initialCategory: state.extra as String?), state),
      ),
      GoRoute(
        path: AppRoutes.citoyenSignal,
        pageBuilder: (context, state) =>
            _fadeThrough(const SignalPage(), state),
      ),
      GoRoute(
        path: AppRoutes.prestaLogin,
        pageBuilder: (context, state) =>
            _fadeThrough(const LoginPrestaPage(), state),
      ),
      GoRoute(
        path: AppRoutes.identityVerification,
        pageBuilder: (context, state) =>
            _fadeThrough(const CertificationPage(), state),
      ),
      GoRoute(
        path: AppRoutes.dashboardParticulier,
        pageBuilder: (context, state) =>
            _fadeThrough(const DashboardParticulierPage(), state),
      ),
      GoRoute(
        path: AppRoutes.dashboardEntreprise,
        pageBuilder: (context, state) =>
            _fadeThrough(const DashboardEntreprisePage(), state),
      ),
    ],
  );
});
