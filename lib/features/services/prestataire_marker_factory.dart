import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/bordereau.dart';

/// Génère des icônes de marqueur Google Maps circulaires affichant la photo
/// du prestataire (avec repli sur une silhouette si pas de photo), un
/// anneau à la couleur de son service principal (même code couleur que les onglets et
/// les fiches), et un point vert s'il est disponible.
///
/// Les bitmaps sont mis en cache par prestataire pour éviter de refaire le
/// rendu (réseau + Canvas) à chaque reconstruction de la carte.
class PrestataireMarkerFactory {
  PrestataireMarkerFactory._();

  static final Map<String, BitmapDescriptor> _cache = {};

  /// Taille logique du marqueur en pixels (avant application du ratio de
  /// densité de l'écran, géré par [devicePixelRatio]).
  static const double _size = 44;

  static Future<BitmapDescriptor> build({
    required String id,
    String? photoUrl,
    String? service,
    bool isOnline = true,
    double devicePixelRatio = 2.5,
  }) async {
    final cacheKey = '$id|${photoUrl ?? ''}|$isOnline|${service ?? ''}';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final bitmap = await _render(
      photoUrl: photoUrl,
      trade: ServiceStyle.of(service),
      isOnline: isOnline,
      devicePixelRatio: devicePixelRatio,
    );
    _cache[cacheKey] = bitmap;
    return bitmap;
  }

  static BitmapDescriptor? _user;

  /// Marqueur « Vous » : point rouge cerclé de blanc dans un halo rouge,
  /// bien distinct des prestataires.
  static Future<BitmapDescriptor> buildUser(
      {double devicePixelRatio = 2.5}) async {
    final cached = _user;
    if (cached != null) return cached;
    const size = 40.0;
    final physical = size * devicePixelRatio;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, physical, physical));
    canvas.scale(devicePixelRatio);
    const center = Offset(size / 2, size / 2);
    const red = Color(0xFFD32F2F);
    canvas.drawCircle(
        center, size / 2, Paint()..color = red.withValues(alpha: 0.18));
    canvas.drawCircle(center, size * 0.3, Paint()..color = Colors.white);
    canvas.drawCircle(center, size * 0.23, Paint()..color = red);
    canvas.drawCircle(center, size * 0.08, Paint()..color = Colors.white);
    final img = await recorder
        .endRecording()
        .toImage(physical.round(), physical.round());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return _user = BitmapDescriptor.bytes(bytes!.buffer.asUint8List(),
        imagePixelRatio: devicePixelRatio);
  }

  static Future<BitmapDescriptor> _render({
    required String? photoUrl,
    required ServiceStyle trade,
    required bool isOnline,
    required double devicePixelRatio,
  }) async {
    const logicalSize = _size;
    final physicalSize = (logicalSize * devicePixelRatio);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, physicalSize, physicalSize),
    );
    canvas.scale(devicePixelRatio);

    // Toutes les dimensions dérivent de logicalSize pour rester bien
    // proportionnées quelle que soit la taille choisie pour le marqueur.
    const center =
        Offset(logicalSize / 2, logicalSize / 2 - logicalSize * 0.035);
    const photoRadius = logicalSize / 2 - logicalSize * 0.12;
    const ringGap = logicalSize * 0.07;
    const ringStroke = logicalSize * 0.045;

    // Halo d'ombre douce derrière le marqueur.
    canvas.drawCircle(
      center.translate(0, logicalSize * 0.026),
      photoRadius + ringGap + logicalSize * 0.01,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter =
            const MaskFilter.blur(BlurStyle.normal, logicalSize * 0.035),
    );

    // Anneau blanc puis anneau à la couleur du service.
    canvas.drawCircle(
        center, photoRadius + ringGap, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      photoRadius + ringGap,
      Paint()
        ..color = trade.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringStroke,
    );

    final clipPath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: photoRadius));
    canvas.save();
    canvas.clipPath(clipPath);

    final image = photoUrl != null && photoUrl.isNotEmpty
        ? await _tryLoadImage(photoUrl)
        : null;

    if (image != null) {
      final dst = Rect.fromCircle(center: center, radius: photoRadius);
      // "Cover" : on centre le crop sur le carré central de l'image.
      final side = image.width < image.height ? image.width : image.height;
      final cropped = Rect.fromCenter(
        center: Offset(image.width / 2, image.height / 2),
        width: side.toDouble(),
        height: side.toDouble(),
      );
      canvas.drawImageRect(image, cropped, dst, Paint());
    } else {
      canvas.drawCircle(center, photoRadius, Paint()..color = trade.tint);
      _drawPersonGlyph(canvas, center, photoRadius, trade.ink);
    }
    canvas.restore();

    if (isOnline) {
      final dotCenter =
          center.translate(photoRadius * 0.72, photoRadius * 0.72);
      canvas.drawCircle(
          dotCenter, logicalSize * 0.086, Paint()..color = Colors.white);
      canvas.drawCircle(
          dotCenter, logicalSize * 0.06, Paint()..color = AppColors.done);
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(
      physicalSize.round(),
      physicalSize.round(),
    );
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      imagePixelRatio: devicePixelRatio,
    );
  }

  static void _drawPersonGlyph(
      Canvas canvas, Offset center, double radius, Color color) {
    final paint = Paint()..color = color.withValues(alpha: 0.7);
    // Tête.
    canvas.drawCircle(
        center.translate(0, -radius * 0.28), radius * 0.28, paint);
    // Épaules (arc du bas, simulé par un cercle décalé sous la ligne de clip).
    final shoulderRect = Rect.fromCircle(
      center: center.translate(0, radius * 0.55),
      radius: radius * 0.62,
    );
    canvas.drawArc(shoulderRect, 3.4, 2.9, true, paint);
  }

  static Future<ui.Image?> _tryLoadImage(String url) async {
    try {
      final completer = Completer<ui.Image>();
      final stream = NetworkImage(url).resolve(const ImageConfiguration());
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          completer.complete(info.image);
          stream.removeListener(listener);
        },
        onError: (error, stackTrace) {
          if (!completer.isCompleted) completer.completeError(error);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);
      return await completer.future.timeout(const Duration(seconds: 6));
    } catch (_) {
      return null;
    }
  }
}
