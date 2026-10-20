import 'dart:async';

import 'package:flutter/material.dart';

/// Fond « ville » des en-têtes vitrines : photos de la ville en noir et
/// blanc, teintées du vert Wanda (duotone), qui dérivent lentement (Ken
/// Burns) et, s'il y en a plusieurs, se succèdent en fondu.
/// Immobile si le système désactive les animations.
class CityBackdrop extends StatefulWidget {
  final List<String> images;
  final Duration interval;

  const CityBackdrop({
    super.key,
    required this.images,
    this.interval = const Duration(seconds: 6),
  });

  @override
  State<CityBackdrop> createState() => _CityBackdropState();
}

class _CityBackdropState extends State<CityBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift =
      AnimationController(vsync: this, duration: const Duration(seconds: 18));
  Timer? _timer;
  int _index = 0;
  bool _started = false;

  static const _greyscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) return;
    _drift.repeat(reverse: true);
    if (widget.images.length > 1) {
      _timer = Timer.periodic(widget.interval, (_) {
        if (mounted) {
          setState(() => _index = (_index + 1) % widget.images.length);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      ClipRect(
        child: AnimatedBuilder(
          animation: _drift,
          builder: (context, child) {
            final t = Curves.easeInOut.transform(_drift.value);
            return Transform.scale(
              scale: 1.08 + 0.08 * t,
              alignment: Alignment(-0.4 + 0.8 * t, 0),
              child: child,
            );
          },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 1200),
            child: ColorFiltered(
              key: ValueKey(_index),
              colorFilter: _greyscale,
              child: Image(
                image:
                    ResizeImage(AssetImage(widget.images[_index]), width: 1080),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
        ),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xD90E5A3A), Color(0xF00A4029)],
          ),
        ),
      ),
    ]);
  }
}
