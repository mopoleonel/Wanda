import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Système de design Wanda — « le bordereau tamponné ».
///
/// Chaque signalement, demande ou mission est une fiche numérotée que la
/// ville tamponne à chaque étape. Le monde visuel en découle :
/// - un fond clair « papier » (l'app s'utilise dehors, en plein soleil) ;
/// - un vert administratif profond pour les en-têtes (papier à en-tête,
///   couleur de marque conservée) ;
/// - une encre de tampon violette réservée aux statuts ;
/// - des copies carbone colorées comme code couleur fixe par métier
///   (voir `TradeStyle`) ;
/// - des filets d'un pixel plutôt que des ombres.
class AppColors {
  AppColors._();

  // --- Papier & encre ---
  static const paper = Color(0xFFF3F6F1); // fond de page
  static const surface = Colors.white; // fiches, cartes, champs
  static const surfaceSunk = Color(0xFFE9EEE7); // zones en creux, pistes
  static const ink = Color(0xFF14201A); // texte principal (15:1 sur blanc)
  static const inkSoft = Color(0xFF46564D); // texte secondaire (7.5:1)
  static const inkMuted = Color(0xFF66766D); // légendes (4.7:1)
  static const rule = Color(0x2914201A); // filet d'un pixel (ink 16 %)
  static const ruleStrong = Color(0x4D14201A);

  // --- En-tête officiel (vert Wanda) ---
  static const letterhead = Color(0xFF0E5A3A);
  static const letterheadDeep = Color(0xFF0A4029);
  static const onLetterhead = Colors.white;
  static const onLetterheadSoft = Color(0xFFC9E3D3);
  static const brandLeaf = Color(0xFF8BD14A); // vert clair du logo
  static const greenTint = Color(0xFFE2EFE6);

  // --- Encre de tampon & statuts ---
  static const stampViolet = Color(0xFF5B3CC4);
  static const stampVioletTint = Color(0xFFECE7FB);
  static const progress = Color(0xFF9A5B00); // en cours (ambre encre)
  static const progressTint = Color(0xFFFCEFD6);
  static const done = Color(0xFF1E7A46); // résolu / terminé
  static const doneTint = Color(0xFFDDF1E4);
  static const danger = Color(0xFFC2362B); // annulé, refus, erreur
  static const dangerTint = Color(0xFFFBE3E0);
  static const gold = Color(0xFFB8860B); // étoiles de note (lisible sur blanc)
}

/// Deux familles : Archivo (grotesque à l'allure administrative, lisible en
/// extérieur) pour tout le texte, Barlow Condensed pour ce qui est
/// « tamponné » ou « numéroté » (statuts, numéros de fiche, chiffres).
class AppText {
  AppText._();

  static TextStyle display = GoogleFonts.archivo(
    color: AppColors.ink,
    fontSize: 30,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
    height: 1.08,
  );

  static TextStyle heading = GoogleFonts.archivo(
    color: AppColors.ink,
    fontSize: 24,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    height: 1.12,
  );

  static TextStyle sectionTitle = GoogleFonts.archivo(
    color: AppColors.ink,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    height: 1.2,
  );

  static TextStyle cardTitle = GoogleFonts.archivo(
    color: AppColors.ink,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.1,
    height: 1.2,
  );

  static TextStyle body = GoogleFonts.archivo(
    color: AppColors.inkSoft,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static TextStyle bodyStrong = GoogleFonts.archivo(
    color: AppColors.ink,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static TextStyle caption = GoogleFonts.archivo(
    color: AppColors.inkMuted,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  static TextStyle label = GoogleFonts.archivo(
    color: AppColors.ink,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  static TextStyle button = GoogleFonts.archivo(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.1,
  );

  /// Capitales de tampon (statuts).
  static TextStyle stamp = GoogleFonts.barlowCondensed(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.6,
    height: 1,
  );

  /// Numéros de fiche, distances, compteurs : chiffres tabulaires.
  static TextStyle number = GoogleFonts.barlowCondensed(
    color: AppColors.ink,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

class AppRadius {
  AppRadius._();
  static const field = 12.0;
  static const card = 14.0;
  static const sheet = 24.0;
  static const chip = 10.0;
  static const pill = 999.0;
}

class AppSpace {
  AppSpace._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// Marge latérale de toutes les pages.
  static const gutter = 20.0;
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.letterhead,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.letterhead,
      onPrimary: Colors.white,
      primaryContainer: AppColors.greenTint,
      onPrimaryContainer: AppColors.letterheadDeep,
      secondary: AppColors.stampViolet,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.stampVioletTint,
      onSecondaryContainer: AppColors.stampViolet,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.inkSoft,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: AppColors.paper,
      surfaceContainer: AppColors.surfaceSunk,
      surfaceContainerHigh: AppColors.surfaceSunk,
      surfaceContainerHighest: AppColors.surfaceSunk,
      outline: AppColors.ruleStrong,
      outlineVariant: AppColors.rule,
      error: AppColors.danger,
      onError: Colors.white,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.paper,
      splashFactory: InkSparkle.splashFactory,
    );

    final textTheme = GoogleFonts.archivoTextTheme(base.textTheme).apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    );

    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.field),
      borderSide: const BorderSide(color: AppColors.ruleStrong),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.paper,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppText.sectionTitle,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.rule,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.rule),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.letterhead,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.surfaceSunk,
          disabledForegroundColor: AppColors.inkMuted,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: AppText.button,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.letterhead,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 52),
          textStyle: AppText.button,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size(64, 52),
          side: const BorderSide(color: AppColors.ruleStrong),
          textStyle: AppText.button,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.letterhead,
          minimumSize: const Size(48, 48),
          textStyle: AppText.label,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: AppText.body.copyWith(color: AppColors.inkMuted),
        floatingLabelStyle: AppText.label.copyWith(color: AppColors.letterhead),
        hintStyle: AppText.body.copyWith(color: AppColors.inkMuted),
        prefixIconColor: AppColors.inkSoft,
        border: fieldBorder,
        enabledBorder: fieldBorder,
        disabledBorder: fieldBorder.copyWith(
            borderSide: const BorderSide(color: AppColors.rule)),
        focusedBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.letterhead, width: 2),
        ),
        errorBorder: fieldBorder.copyWith(
            borderSide: const BorderSide(color: AppColors.danger)),
        focusedErrorBorder: fieldBorder.copyWith(
            borderSide: const BorderSide(color: AppColors.danger, width: 2)),
        errorStyle: AppText.caption.copyWith(color: AppColors.danger),
        helperStyle: AppText.caption,
        helperMaxLines: 2,
        errorMaxLines: 2,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 72,
        indicatorColor: AppColors.greenTint,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return AppText.caption.copyWith(
            color: selected ? AppColors.letterheadDeep : AppColors.inkSoft,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppColors.letterheadDeep : AppColors.inkSoft,
            size: 24,
          );
        }),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(AppText.label),
          side: const WidgetStatePropertyAll(
              BorderSide(color: AppColors.ruleStrong)),
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? AppColors.greenTint
                  : AppColors.surface),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? AppColors.letterheadDeep
                  : AppColors.inkSoft),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.rule),
        labelStyle: AppText.label,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.ruleStrong,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppText.sectionTitle,
        contentTextStyle: AppText.body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: AppText.body.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.letterhead,
        linearTrackColor: AppColors.surfaceSunk,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? Colors.white
                : AppColors.inkMuted),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.done
                : AppColors.surfaceSunk),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.inkSoft,
        titleTextStyle: AppText.bodyStrong,
        subtitleTextStyle: AppText.caption,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.letterhead,
        selectionColor: AppColors.letterhead.withValues(alpha: 0.22),
        selectionHandleColor: AppColors.letterhead,
      ),
    );
  }
}
