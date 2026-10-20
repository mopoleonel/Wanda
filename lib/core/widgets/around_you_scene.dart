import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'bordereau.dart';

/// Scène décorative « autour de vous » : vous au centre (ondes), les quatre
/// services qui flottent autour, chacun dans sa couleur carbone.
class AroundYouScene extends StatefulWidget {
  const AroundYouScene({super.key});

  @override
  State<AroundYouScene> createState() => AroundYouSceneSceneState();
}

class AroundYouSceneSceneState extends State<AroundYouScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.disableAnimationsOf(context) && !_t.isAnimating) {
      _t.repeat();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trades = ServiceStyle.codes.skip(1).toList();
    return ExcludeSemantics(
      child: LayoutBuilder(builder: (context, c) {
        final side = math.min(c.maxWidth, c.maxHeight);
        final orbit = side * 0.36;
        final bubble = (side * 0.2).clamp(40.0, 60.0);
        return AnimatedBuilder(
          animation: _t,
          builder: (context, _) {
            return SizedBox(
              width: c.maxWidth,
              height: c.maxHeight,
              child: Stack(alignment: Alignment.center, children: [
                Positioned.fill(
                  child: CustomPaint(painter: _RingsPainter(_t.value)),
                ),
                Container(
                  width: bubble * 0.95,
                  height: bubble * 0.95,
                  decoration: const BoxDecoration(
                    color: AppColors.brandLeaf,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.person_pin_circle_rounded,
                      color: AppColors.letterheadDeep, size: bubble * 0.6),
                ),
                for (var i = 0; i < trades.length; i++)
                  _bubble(ServiceStyle.of(trades[i]), i, trades.length, orbit,
                      bubble),
              ]),
            );
          },
        );
      }),
    );
  }

  Widget _bubble(ServiceStyle t, int i, int n, double orbit, double size) {
    // Positions fixes en losange, chacune flotte doucement à son rythme.
    final angle = -math.pi / 2 + i * 2 * math.pi / n + math.pi / n;
    final phase = _t.value * 2 * math.pi + i * 1.7;
    final dx = math.cos(angle) * orbit * 1.35;
    final dy = math.sin(angle) * orbit + math.sin(phase) * 5;
    return Transform.translate(
      offset: Offset(dx, dy),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: t.tint,
          borderRadius: BorderRadius.circular(size * 0.3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(t.icon, color: t.ink, size: size * 0.5),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  final double t;
  _RingsPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final rMax = math.min(size.width, size.height) / 2;
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      canvas.drawCircle(
        center,
        rMax * (0.15 + 0.85 * p),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = AppColors.brandLeaf.withValues(alpha: (1 - p) * 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter old) => old.t != t;
}
