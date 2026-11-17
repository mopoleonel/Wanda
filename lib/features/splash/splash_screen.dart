import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/session.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/bordereau.dart';

/// Où ouvrir l'app au lancement : l'espace du compte resté connecté, sinon
/// l'accueil. Lu dans la session gardée sur le téléphone : marche aussi sans
/// réseau. On ne sort d'un compte qu'en touchant « Se déconnecter ».
String destinationAuLancement(Session? session) =>
    switch (session?.typeCompte) {
      'citoyen' => AppRoutes.citoyenServices,
      'particulier' => AppRoutes.dashboardParticulier,
      'entreprise' => AppRoutes.dashboardEntreprise,
      // Pas de session, ou inscription prestataire pas finie (type pas
      // encore choisi) : l'accueil.
      _ => AppRoutes.home,
    };

/// Écran de lancement : la bande verte officielle, le logo, le slogan.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 2200);

  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _duration);
  late final Animation<double> _enter = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.45, curve: Curves.easeOutExpo),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    // Compte déjà connecté : lancement plus court, on va droit à l'espace.
    final session = ref.read(gestionSessionProvider).courante;
    final destination = destinationAuLancement(session);
    _timer = Timer(
        destination == AppRoutes.home
            ? _duration
            : const Duration(milliseconds: 900), () {
      if (mounted) context.go(destination);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: AppColors.letterhead,
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),
              AnimatedBuilder(
                animation: _enter,
                builder: (context, child) {
                  final t = reduceMotion ? 1.0 : _enter.value;
                  return Opacity(
                    opacity: t,
                    child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
                  );
                },
                child: Column(children: [
                  const WandaMark(size: 132),
                  const SizedBox(height: 28),
                  Text(
                    'WANDA',
                    style: AppText.display.copyWith(
                      color: Colors.white,
                      fontSize: 40,
                      letterSpacing: 8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "L'œil intelligent de la ville",
                    style: AppText.body.copyWith(
                      color: AppColors.onLetterheadSoft,
                      fontSize: 16,
                    ),
                  ),
                ]),
              ),
              const Spacer(flex: 4),
              Padding(
                padding: const EdgeInsets.fromLTRB(64, 0, 64, 40),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => LinearProgressIndicator(
                      value: _controller.value,
                      minHeight: 3,
                      color: AppColors.brandLeaf,
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
