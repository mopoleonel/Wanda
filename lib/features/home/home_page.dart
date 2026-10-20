import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/bordereau.dart';
import '../../core/widgets/city_backdrop.dart';

/// Accueil : la ville en duotone vert, « l'œil » qui veille (ondes radar
/// autour du logo), une fiche d'exemple dont le tampon avance tout seul
/// (REÇU → EN COURS → RÉSOLU) pour montrer le principe, puis le choix du
/// rôle. Toutes les animations se coupent si le système les désactive.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600));

  /// Démo : une demande de service avance (envoyée → confirmée →
  /// terminée), puis on passe au service suivant.
  static const _demoTrades = ['menage', 'linge', 'dechets', 'nuisibles'];
  int _demoStep = 0;
  int _demoTrade = 0;
  Timer? _demoTimer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
      _demoStep = 2;
      return;
    }
    _intro.forward();
    _pulse.repeat();
    _demoTimer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
      if (!mounted) return;
      setState(() {
        _demoStep = (_demoStep + 1) % 3;
        if (_demoStep == 0) {
          _demoTrade = (_demoTrade + 1) % _demoTrades.length;
        }
      });
    });
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  /// Apparition décalée : chaque bloc glisse et apparaît dans sa fenêtre.
  Widget _reveal(double start, Widget child) {
    final anim = CurvedAnimation(
      parent: _intro,
      curve: Interval(start, math.min(start + 0.45, 1),
          curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      child: child,
      builder: (context, child) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
            offset: Offset(0, 24 * (1 - anim.value)), child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final screen = MediaQuery.sizeOf(context);

    // Tout tient sur un seul écran : l'en-tête prend l'espace restant, le
    // bas (démo + rôles) garde sa hauteur naturelle. Pas de défilement.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildHero()),
            // La fiche d'exemple chevauche le bord perforé de l'en-tête ;
            // le bas de page remonte d'autant.
            Transform.translate(
              offset: const Offset(0, -_overlap),
              // Le bas de page ne dépasse jamais 60 % de l'écran : avec une
              // police système agrandie, il se réduit au lieu d'écraser
              // l'en-tête ou de déborder.
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: screen.height * 0.6),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: screen.width,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                          AppSpace.gutter,
                          0,
                          AppSpace.gutter,
                          math.max(0, bottomInset + AppSpace.md - _overlap)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _reveal(
                              0.35,
                              _DemoRequest(
                                  code: _demoTrades[_demoTrade],
                                  step: _demoStep)),
                          _reveal(
                              0.45,
                              Padding(
                                padding: const EdgeInsets.only(
                                    top: AppSpace.lg, bottom: AppSpace.sm),
                                child: Text('Vous êtes…',
                                    style: AppText.sectionTitle),
                              )),
                          _reveal(
                            0.5,
                            _RoleFiche(
                              title: 'Citoyen',
                              description:
                                  'Ménage, linge, poubelles, nuisibles : à prix fixe.',
                              icon: Icons.person_rounded,
                              tint: AppColors.greenTint,
                              ink: AppColors.letterheadDeep,
                              primary: true,
                              onTap: () => context.push(ref
                                          .read(authRepositoryProvider)
                                          .currentUserId !=
                                      null
                                  ? AppRoutes.citoyenServices
                                  : AppRoutes.citoyenLogin),
                            ),
                          ),
                          const SizedBox(height: AppSpace.sm),
                          _reveal(
                            0.6,
                            _RoleFiche(
                              title: 'Prestataire',
                              description:
                                  'Proposez vos services ou recevez des missions.',
                              icon: Icons.business_center_rounded,
                              tint: AppColors.stampVioletTint,
                              ink: AppColors.stampViolet,
                              onTap: () => context.push(AppRoutes.prestaLogin),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const double _overlap = 36;

  Widget _buildHero() {
    return LayoutBuilder(
        builder: (context, c) => _buildHeroContent(
            compact: c.maxHeight < 330,
            height: c.maxHeight,
            width: c.maxWidth));
  }

  /// [compact] : petit écran, on garde le titre (plus petit) et on retire
  /// la phrase d'accroche pour que tout tienne sans défiler.
  Widget _buildHeroContent(
      {required bool compact, required double height, required double width}) {
    final topInset = MediaQuery.paddingOf(context).top;
    const bottomPad = 52.0;
    const topRow = 28.0;
    // Hauteur maximale du bloc titre : s'il n'a pas la place (police système
    // agrandie, très petit écran), il se réduit au lieu de déborder.
    final maxTextH =
        math.max(40.0, height - topInset - AppSpace.md - bottomPad - topRow);
    final textW = width - 2 * AppSpace.gutter;
    return Stack(fit: StackFit.expand, children: [
      const CityBackdrop(images: ['assets/images/city2.png']),
      Padding(
        padding: EdgeInsets.fromLTRB(AppSpace.gutter, topInset + AppSpace.md,
            AppSpace.gutter, bottomPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _reveal(
              0,
              Row(children: [
                Text('WANDA',
                    style: AppText.label.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4)),
                const Spacer(),
                Text('Cameroun',
                    style: AppText.caption
                        .copyWith(color: AppColors.onLetterheadSoft)),
              ]),
            ),
            // L'œil occupe l'espace libre ; il rétrécit sur les petits écrans
            // et disparaît s'il n'a vraiment pas la place.
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                final size = math.min(c.maxHeight - 8, 220.0);
                if (size < 96) return const SizedBox.shrink();
                return Center(
                  child: _reveal(
                    0.05,
                    SizedBox.square(
                      dimension: size,
                      child: FittedBox(child: _WatchingEye(pulse: _pulse)),
                    ),
                  ),
                );
              }),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxTextH),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomLeft,
                child: SizedBox(
                  width: textW,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _reveal(
                        0.15,
                        Text(
                          "L'œil intelligent\nde la ville",
                          style: AppText.display.copyWith(
                              color: Colors.white,
                              fontSize: compact ? 26 : 32,
                              height: 1.05),
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(height: AppSpace.sm),
                        _reveal(
                          0.22,
                          Text(
                            'Ménage, linge, poubelles, nuisibles : un prestataire près de chez vous, au prix fixé par WANDA, et vous suivez sa venue.',
                            style: AppText.body
                                .copyWith(color: AppColors.onLetterheadSoft),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      const Positioned(left: 0, right: 0, bottom: 0, child: PerforatedEdge()),
    ]);
  }
}

/// Le logo qui « veille » : des ondes partent de l'œil en continu.
class _WatchingEye extends StatelessWidget {
  final Animation<double> pulse;
  const _WatchingEye({required this.pulse});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(alignment: Alignment.center, children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(painter: _RadarPainter(pulse)),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.brandLeaf.withValues(alpha: 0.35),
                blurRadius: 40,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const WandaMark(size: 112),
        ),
      ]),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final Animation<double> pulse;
  _RadarPainter(this.pulse) : super(repaint: pulse);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const r0 = 58.0;
    final rMax = size.shortestSide / 2;
    for (var i = 0; i < 3; i++) {
      final t = (pulse.value + i / 3) % 1.0;
      final radius = r0 + (rMax - r0) * t;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 - t
        ..color = AppColors.brandLeaf.withValues(alpha: (1 - t) * 0.6);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) => false;
}

/// Exemple de demande de service : le service défile, le tampon avance
/// (ENVOYÉE → CONFIRMÉE → TERMINÉE, les vrais statuts d'une demande).
class _DemoRequest extends StatelessWidget {
  final String code;
  final int step;
  const _DemoRequest({required this.code, required this.step});

  ServiceStyle get trade => ServiceStyle.of(code);

  static const _stamps = [
    FicheStatus('ENVOYÉE', StampTone.received),
    FicheStatus('CONFIRMÉE', StampTone.progress),
    FicheStatus('TERMINÉE', StampTone.done),
  ];
  static const _lines = [
    'Prix fixé par WANDA, demande envoyée',
    'Un prestataire proche a confirmé',
    'Service terminé, vous notez',
  ];

  /// Titre de l'exemple, par service.
  static const _titres = {
    'menage': 'Grand ménage, 3 pièces',
    'linge': 'Lessive et repassage',
    'dechets': 'Poubelles, 2 fois par semaine',
    'nuisibles': 'Traitement anti-cafards',
  };
  static const _icons = [
    Icons.wifi_tethering_rounded,
    Icons.directions_walk_rounded,
    Icons.star_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final ink = _stamps[step].ink;
    return Semantics(
      label:
          "Exemple : une demande de service passe d'envoyée à confirmée puis terminée.",
      excludeSemantics: true,
      child: FicheCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: trade.tint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: AnimatedSwitcher(
                  switchOutCurve: const Threshold(1),
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, a) =>
                      ScaleTransition(scale: a, child: child),
                  child: Icon(trade.icon,
                      key: ValueKey(trade.label), color: trade.ink, size: 28),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Exemple de demande',
                        style: AppText.caption.copyWith(fontSize: 12)),
                    AnimatedSwitcher(
                      switchOutCurve: const Threshold(1),
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween(
                                  begin: const Offset(0, 0.4), end: Offset.zero)
                              .animate(a),
                          child: child,
                        ),
                      ),
                      child: Text(
                        _titres[code] ?? trade.libelle,
                        key: ValueKey(code),
                        style: AppText.cardTitle.copyWith(fontSize: 17),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              StatusStamp(_stamps[step]),
            ]),
            const SizedBox(height: AppSpace.lg),
            AnimatedSwitcher(
              switchOutCurve: const Threshold(1),
              duration: const Duration(milliseconds: 300),
              child: Row(key: ValueKey(step), children: [
                Icon(_icons[step], size: 18, color: ink),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: Text(_lines[step], style: AppText.bodyStrong)),
              ]),
            ),
            const SizedBox(height: AppSpace.md),
            _StepTrack(step: step),
          ],
        ),
      ),
    );
  }
}

class _StepTrack extends StatelessWidget {
  final int step;
  const _StepTrack({required this.step});

  @override
  Widget build(BuildContext context) {
    const labels = ['Envoyée', 'Confirmée', 'Terminée'];
    const inks = [AppColors.stampViolet, AppColors.progress, AppColors.done];
    return Row(
      children: List.generate(3, (i) {
        final active = i <= step;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < 2 ? 6 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  height: 4,
                  decoration: BoxDecoration(
                    color: active ? inks[step] : AppColors.surfaceSunk,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Text(labels[i],
                    style: AppText.caption.copyWith(
                        fontSize: 12,
                        color: active ? AppColors.ink : AppColors.inkMuted,
                        fontWeight: active ? FontWeight.w700 : null)),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _RoleFiche extends StatefulWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color tint;
  final Color ink;
  final bool primary;
  final VoidCallback onTap;

  const _RoleFiche({
    required this.title,
    required this.description,
    required this.icon,
    required this.tint,
    required this.ink,
    required this.onTap,
    this.primary = false,
  });

  @override
  State<_RoleFiche> createState() => _RoleFicheState();
}

class _RoleFicheState extends State<_RoleFiche> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Continuer en tant que ${widget.title}',
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: FicheCard(
            onTap: widget.onTap,
            color: widget.primary ? AppColors.letterhead : null,
            padding: const EdgeInsets.all(AppSpace.lg + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  // Même gabarit pour les deux rôles : les titres s'alignent.
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: widget.primary
                          ? Colors.white.withValues(alpha: 0.14)
                          : widget.tint,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(widget.icon,
                        color: widget.primary ? Colors.white : widget.ink,
                        size: widget.primary ? 30 : 26),
                  ),
                  const SizedBox(width: AppSpace.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            style: widget.primary
                                ? AppText.sectionTitle
                                    .copyWith(fontSize: 21, color: Colors.white)
                                : AppText.cardTitle),
                        const SizedBox(height: 2),
                        Text(widget.description,
                            style: AppText.caption.copyWith(
                                color: widget.primary
                                    ? AppColors.onLetterheadSoft
                                    : null)),
                      ],
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.primary
                          ? AppColors.brandLeaf
                          : AppColors.surfaceSunk,
                    ),
                    child: Icon(Icons.arrow_forward_rounded,
                        size: 22,
                        color: widget.primary
                            ? AppColors.letterheadDeep
                            : AppColors.inkSoft),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
