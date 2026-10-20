import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/avis_prestataire.dart';
import '../theme/app_theme.dart';

// =============================================================================
// Briques du monde « bordereau tamponné » : tampons de statut, numéros de
// fiche, en-tête officiel perforé, code couleur par métier, photo d'identité.
// =============================================================================

/// Teinte d'encre d'un tampon.
/// `live` : encre claire réservée aux tampons posés sur la bande verte.
enum StampTone { received, progress, done, live, cancelled, archived }

extension on StampTone {
  Color get ink => switch (this) {
        StampTone.received => AppColors.stampViolet,
        StampTone.progress => AppColors.progress,
        StampTone.done => AppColors.done,
        StampTone.live => AppColors.brandLeaf,
        StampTone.cancelled => AppColors.danger,
        StampTone.archived => AppColors.inkMuted,
      };
}

/// Libellé + encre d'un statut, pour les trois types de fiches de l'app.
class FicheStatus {
  final String label;
  final StampTone tone;
  const FicheStatus(this.label, this.tone);

  Color get ink => tone.ink;

  /// Sollicitation citoyen → prestataire.
  factory FicheStatus.sollicitation(String statut) => switch (statut) {
        'accepte' => const FicheStatus('EN ROUTE', StampTone.progress),
        'termine' => const FicheStatus('TERMINÉ', StampTone.done),
        'archive' => const FicheStatus('CLASSÉ', StampTone.archived),
        'annule' => const FicheStatus('ANNULÉ', StampTone.cancelled),
        _ => const FicheStatus('REÇU', StampTone.received),
      };

  /// Signalement urbain traité par une entreprise.
  factory FicheStatus.signalement(String statut) => switch (statut) {
        'en_cours' => const FicheStatus('EN COURS', StampTone.progress),
        'resolu' => const FicheStatus('RÉSOLU', StampTone.done),
        'rejete' => const FicheStatus('REJETÉ', StampTone.cancelled),
        _ => const FicheStatus('REÇU', StampTone.received),
      };
}

/// Le tampon : double filet, capitales espacées, légère inclinaison. Quand
/// le statut change, le nouveau tampon « tombe » sur la fiche (échelle +
/// fondu). Respecte le réglage système « supprimer les animations ».
class StatusStamp extends StatelessWidget {
  final FicheStatus status;
  final double angle;
  final bool large;

  const StatusStamp(this.status,
      {super.key, this.angle = -4, this.large = false});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final stamp = _StampFace(
      key: ValueKey(status.label),
      status: status,
      large: large,
    );
    return Semantics(
      label: 'Statut : ${status.label.toLowerCase()}',
      excludeSemantics: true,
      child: Transform.rotate(
        angle: angle * math.pi / 180,
        child: reduceMotion
            ? stamp
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 380),
                switchInCurve: Curves.easeOutExpo,
                // L'ancien tampon disparaît d'un coup : pas de chevauchement.
                switchOutCurve: const Threshold(1),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(
                    scale: Tween(begin: 1.35, end: 1.0).animate(anim),
                    child: child,
                  ),
                ),
                child: stamp,
              ),
      ),
    );
  }
}

class _StampFace extends StatelessWidget {
  final FicheStatus status;
  final bool large;
  const _StampFace({super.key, required this.status, required this.large});

  @override
  Widget build(BuildContext context) {
    final ink = status.ink;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ink.withValues(alpha: 0.9), width: 2),
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: large ? 12 : 7, vertical: large ? 7 : 4),
        decoration: BoxDecoration(
          color: ink.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: ink.withValues(alpha: 0.7), width: 1),
        ),
        child: Text(
          status.label,
          style: AppText.stamp.copyWith(
            color: ink,
            fontSize: large ? 18 : 13,
            letterSpacing: large ? 2.4 : 1.6,
          ),
        ),
      ),
    );
  }
}

/// « N° 004213 » : identifiant lisible d'une fiche, dérivé de son id
/// (numérique ou uuid) pour que le citoyen puisse la citer au téléphone.
String ficheNumber(String id) {
  final digits = int.tryParse(id);
  if (digits != null) return 'N° ${digits.toString().padLeft(6, '0')}';
  final clean = id.replaceAll('-', '').toUpperCase();
  return 'N° ${clean.length >= 6 ? clean.substring(0, 6) : clean}';
}

/// Durée écoulée lisible : « à l'instant », « il y a 12 min », « il y a 3 h »,
/// « il y a 8 j ».
String sinceLabel(DateTime date) {
  final d = DateTime.now().difference(date);
  if (d.inMinutes < 1) return "à l'instant";
  if (d.inHours < 1) return 'il y a ${d.inMinutes} min';
  if (d.inDays < 1) return 'il y a ${d.inHours} h';
  return 'il y a ${d.inDays} j';
}

/// Distance au format français : « 850 m », « 5,8 km ».
String distanceLabel(double meters) => meters < 1000
    ? '${meters.round()} m'
    : '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

class FicheNumber extends StatelessWidget {
  final String id;
  final Color? color;
  const FicheNumber(this.id, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      ficheNumber(id),
      style: AppText.number.copyWith(
        fontSize: 13.5,
        color: color ?? AppColors.inkMuted,
        letterSpacing: 0.8,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Code couleur par métier : une « copie carbone » par métier, identique sur
// les onglets, les fiches et la carte.
// -----------------------------------------------------------------------------

class TradeStyle {
  final String label;
  final IconData icon;
  final Color tint; // fond carbone
  final Color ink; // texte / icône sur ce fond

  const TradeStyle(this.label, this.icon, this.tint, this.ink);

  static const all = TradeStyle('Tous', Icons.apps_rounded, AppColors.greenTint,
      AppColors.letterheadDeep);

  static const _byName = <String, TradeStyle>{
    'Plombier': TradeStyle('Plombier', Icons.plumbing_rounded,
        Color(0xFFD8E7F8), Color(0xFF1B4F8C)),
    'Électricien': TradeStyle('Électricien', Icons.electrical_services_rounded,
        Color(0xFFF7E9A6), Color(0xFF6E5400)),
    'Maçon': TradeStyle('Maçon', Icons.construction_rounded, Color(0xFFF6D8DF),
        Color(0xFF8E2F4C)),
    'Froid & Clim': TradeStyle('Froid & Clim', Icons.ac_unit_rounded,
        Color(0xFFD5EEEA), Color(0xFF14665A)),
  };

  static List<String> get names => ['Tous', ..._byName.keys];

  static TradeStyle of(String? name) {
    if (name == null || name.isEmpty || name == 'Tous') return all;
    return _byName[name] ??
        TradeStyle(name, Icons.handyman_rounded, AppColors.surfaceSunk,
            AppColors.inkSoft);
  }
}

/// Étiquette métier compacte (copie carbone).
class TradeTag extends StatelessWidget {
  final String? trade;

  /// Libellé quand aucun métier n'est renseigné.
  final String emptyLabel;
  const TradeTag(this.trade, {this.emptyLabel = 'Expert', super.key});

  @override
  Widget build(BuildContext context) {
    final t = TradeStyle.of(trade);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.tint,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(t.icon, size: 14, color: t.ink),
        const SizedBox(width: 4),
        Text(
          trade == null || trade!.isEmpty ? emptyLabel : t.label,
          style: AppText.caption.copyWith(
              color: t.ink, fontWeight: FontWeight.w700, fontSize: 12.5),
        ),
      ]),
    );
  }
}

// -----------------------------------------------------------------------------
// Photo d'identité (carrée, coins doux, filet) — comme agrafée sur la fiche.
// -----------------------------------------------------------------------------

class IdPhoto extends StatelessWidget {
  final String? url;
  final double size;
  final IconData fallbackIcon;
  final Color? tint;

  const IdPhoto({
    super.key,
    required this.url,
    this.size = 56,
    this.fallbackIcon = Icons.person_rounded,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = url != null && url!.isNotEmpty;
    final radius = BorderRadius.circular(size * 0.18);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint ?? AppColors.surfaceSunk,
        borderRadius: radius,
        border: Border.all(color: AppColors.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? Image.network(
              url!,
              fit: BoxFit.cover,
              cacheWidth: (size * 3).round(),
              errorBuilder: (_, __, ___) => _fallback(),
            )
          : _fallback(),
    );
  }

  Widget _fallback() => Icon(fallbackIcon,
      size: size * 0.48, color: AppColors.inkMuted.withValues(alpha: 0.8));
}

/// Note ★ 4,6 (12) ou « Nouveau ».
class RatingInline extends StatelessWidget {
  final RatingSummary rating;
  const RatingInline(this.rating, {super.key});

  @override
  Widget build(BuildContext context) {
    final hasRating = rating.count > 0;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (hasRating) ...[
        const Icon(Icons.star_rounded, size: 16, color: AppColors.gold),
        const SizedBox(width: 3),
        Text(
          '${rating.average.toStringAsFixed(1).replaceAll('.', ',')} (${rating.count})',
          style: AppText.number.copyWith(fontSize: 14, color: AppColors.ink),
        ),
      ] else
        Text('Nouveau',
            style: AppText.caption.copyWith(
                color: AppColors.stampViolet, fontWeight: FontWeight.w700)),
    ]);
  }
}

// -----------------------------------------------------------------------------
// En-tête officiel : bande verte (papier à en-tête), bord perforé.
// -----------------------------------------------------------------------------

class Letterhead extends StatelessWidget {
  final String title;
  final String? overline;
  final String? subtitle;
  final bool showBack;
  final bool showLogo;
  final Widget? trailing;
  final Widget? bottom;

  const Letterhead({
    super.key,
    required this.title,
    this.overline,
    this.subtitle,
    this.showBack = false,
    this.showLogo = false,
    this.trailing,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    // Icônes de barre d'état claires sur la bande verte.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light
          .copyWith(statusBarColor: Colors.transparent),
      child: Stack(children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
              AppSpace.gutter, topInset + 8, AppSpace.gutter, 26),
          color: AppColors.letterhead,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showBack ||
                  showLogo ||
                  overline != null ||
                  trailing != null) ...[
                Row(children: [
                  if (showBack) ...[
                    IconButton(
                      onPressed: () => context.canPop()
                          ? context.pop()
                          : Navigator.of(context).maybePop(),
                      tooltip: 'Retour',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (showLogo) ...[
                    const WandaMark(size: 36),
                    const SizedBox(width: 10),
                  ],
                  if (overline != null)
                    Expanded(
                      child: Text(
                        overline!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.label
                            .copyWith(color: AppColors.onLetterheadSoft),
                      ),
                    )
                  else
                    const Spacer(),
                  if (trailing != null) trailing!,
                ]),
                const SizedBox(height: 14),
              ] else
                const SizedBox(height: 16),
              Text(title,
                  style:
                      AppText.heading.copyWith(color: AppColors.onLetterhead)),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!,
                    style: AppText.body
                        .copyWith(color: AppColors.onLetterheadSoft)),
              ],
              if (bottom != null) ...[
                const SizedBox(height: 16),
                bottom!,
              ],
            ],
          ),
        ),
        const Positioned(left: 0, right: 0, bottom: 0, child: PerforatedEdge()),
      ]),
    );
  }
}

/// Le logo Wanda dans une pastille blanche (il est conçu sur fond vert).
class WandaMark extends StatelessWidget {
  final double size;
  const WandaMark({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.04),
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: Transform.scale(
          // Le PNG a une marge blanche : on recadre sur le disque vert.
          scale: 1.45,
          child: Image.asset('assets/images/wanda_logo.png',
              fit: BoxFit.cover,
              cacheWidth: (size * 4).round(),
              semanticLabel: 'Logo WANDA'),
        ),
      ),
    );
  }
}

/// Bord perforé dessiné au-dessus de l'en-tête.
class PerforatedEdge extends StatelessWidget {
  final Color color;
  const PerforatedEdge({super.key, this.color = AppColors.paper});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 6),
      painter: _HolesPainter(color),
    );
  }
}

class _HolesPainter extends CustomPainter {
  final Color color;
  _HolesPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const step = 14.0;
    const r = 4.0;
    for (double x = step / 2; x < size.width; x += step) {
      canvas.drawCircle(Offset(x, size.height), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HolesPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Titre de section : titre à gauche, mention/action à droite.
class SectionTitle extends StatelessWidget {
  final String title;
  final String? trailing;
  final EdgeInsetsGeometry padding;

  const SectionTitle(
    this.title, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
        AppSpace.gutter, AppSpace.xl, AppSpace.gutter, AppSpace.md),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(title,
                style: AppText.sectionTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            Text(trailing!,
                style: AppText.number
                    .copyWith(color: AppColors.inkMuted, fontSize: 14)),
          ],
        ],
      ),
    );
  }
}

/// Fiche : surface blanche, filet d'un pixel, coins modérés.
class FicheCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  const FicheCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Tuile de choix du métier (copie carbone du métier).
class TradeChoiceTile extends StatelessWidget {
  final TradeStyle style;
  final bool selected;
  final VoidCallback onTap;
  const TradeChoiceTile(
      {super.key,
      required this.style,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? style.tint : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(
              color: selected ? style.ink : AppColors.rule,
              width: selected ? 2 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Icon(style.icon, color: style.ink),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(style.label,
                    style: AppText.label
                        .copyWith(color: selected ? style.ink : AppColors.ink)),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: style.ink, size: 20),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Badge « identité vérifiée » à côté du nom d'un artisan certifié.
class VerifiedMark extends StatelessWidget {
  final double size;
  const VerifiedMark({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Identité vérifiée par WANDA',
      child: Icon(Icons.verified_rounded,
          size: size,
          color: AppColors.done,
          semanticLabel: 'Identité vérifiée'),
    );
  }
}
