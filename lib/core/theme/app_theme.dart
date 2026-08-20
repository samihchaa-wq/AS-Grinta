import 'package:as_grinta/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

class _GrintaPageTransitionsBuilder extends PageTransitionsBuilder {
  const _GrintaPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(opacity: curved, child: child);
  }
}

abstract final class AppTheme {
  // ---------------------------------------------------------------------
  // Surfaces
  //
  // Les fonds sont opaques : plus aucune illustration ne passe sous le
  // contenu en dehors de la connexion et du démarrage. C'est ce qui permet
  // de supprimer les contours de texte et de retrouver un rendu net.
  // ---------------------------------------------------------------------

  /// Fond d'écran général.
  static const Color background = Color(0xFF04121F);

  /// Fond de la barre du haut.
  static const Color surfaceBar = Color(0xFF0A1B2E);

  /// Fond de la barre de navigation basse.
  static const Color surfaceBarLow = Color(0xFF07182D);

  /// Carte de niveau 1.
  static const Color surface = Color(0xFF0E2138);

  /// Carte de niveau 2 et champs de saisie.
  static const Color surfaceHigh = Color(0xFF152F4C);

  /// Surface mise en avant (onglet actif, bloc principal).
  static const Color surfaceHero = Color(0xFF17457A);

  /// Filet discret entre deux blocs.
  static const Color outline = Color(0xFF1E3A56);

  /// Bordure marquée d'une carte mise en avant.
  static const Color outlineMarked = Color(0xFF24456A);

  /// Bordure marquée haute (événement club, séparateur affirmé).
  static const Color outlineStrong = Color(0xFF2A527E);

  /// Piste des indicateurs de progression.
  static const Color progressTrack = Color(0xFF17304A);

  // ---------------------------------------------------------------------
  // Couleurs de sens
  //
  // Une seule couleur d'action : le bleu. Le jaune du blason ne signale plus
  // que ce qui concerne le club en direct (prochain match, Live, vote ouvert,
  // sa propre ligne).
  // ---------------------------------------------------------------------

  static const Color primary = Color(0xFF3D7DD8);
  static const Color primaryPressed = Color(0xFF2B5FA8);
  static const Color primaryBright = Color(0xFF6FA8F5);

  /// Repère de club : Live, vote ouvert, prochain match, sa propre ligne.
  static const Color accent = Color(0xFFF2DE3A);

  /// Or des récompenses (badges, trophées). Distinct du repère de club :
  /// il qualifie une distinction obtenue, pas une actualité du club.
  static const Color reward = Color(0xFFFFD84A);

  static const Color success = Color(0xFF3FC489);
  static const Color warning = Color(0xFFE9A03C);
  static const Color error = Color(0xFFE8586B);

  /// Scores : victoire et défaite, légèrement plus saturés que les états.
  static const Color scoreWin = Color(0xFF3BD16F);
  static const Color scoreLoss = Color(0xFFE5555A);

  static const Color admin = primaryBright;

  // ---------------------------------------------------------------------
  // Texte
  // ---------------------------------------------------------------------

  static const Color textPrimary = Color(0xFFEAF2FC);
  static const Color textSecondary = Color(0xFFC7D8EC);
  static const Color textSecondaryDim = Color(0xFFB9CCE2);

  /// Texte tertiaire et textes d'aide.
  static const Color textFaint = Color(0xFF9BB0C8);

  /// Étiquettes et métadonnées.
  static const Color textLabel = Color(0xFF8DA6C2);
  static const Color textLabelDim = Color(0xFF7C93AC);

  static const Color textDisabled = Color(0xFF5E7A98);

  // Grille de 8 px et niveaux de surfaces communs.
  static const double spaceXs = 8;
  static const double spaceSm = 12;
  static const double spaceMd = 16;
  static const double spaceLg = 24;

  /// Onglet, pastille.
  static const double radiusXs = 9;

  /// Bouton, champ de saisie.
  static const double radiusSm = 12;

  /// Carte.
  static const double radiusMd = 16;

  /// Carte mise en avant.
  static const double radiusLg = 22;

  /// Écran plein (terrain, grande surface).
  static const double radiusXl = 26;

  static ShapeBorder cardShape({
    double radius = radiusMd,
    Color? borderColor,
    double borderWidth = 1,
  }) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(
          color: borderColor ?? outline,
          width: borderWidth,
        ),
      );

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: surfaceHero,
      onPrimaryContainer: textPrimary,
      secondary: accent,
      onSecondary: background,
      secondaryContainer: Color(0xFF393506),
      onSecondaryContainer: Color(0xFFFFF6A8),
      tertiary: reward,
      onTertiary: background,
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      surfaceContainerHighest: surfaceHigh,
      error: error,
      // `error` sert de FOND aux boutons de confirmation destructifs
      // (« Supprimer », « Tout effacer »). Blanc sur ce rouge reste sous le
      // seuil WCAG AA même pour du grand texte ; le bleu nuit du fond général
      // le dépasse largement. `error` employé en texte reste inchangé.
      onError: background,
      outline: outline,
      outlineVariant: Color(0xFF173755),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: AppTypography.ui,
      scaffoldBackgroundColor: background,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _GrintaPageTransitionsBuilder(),
          TargetPlatform.iOS: _GrintaPageTransitionsBuilder(),
          TargetPlatform.macOS: _GrintaPageTransitionsBuilder(),
          TargetPlatform.windows: _GrintaPageTransitionsBuilder(),
          TargetPlatform.linux: _GrintaPageTransitionsBuilder(),
          TargetPlatform.fuchsia: _GrintaPageTransitionsBuilder(),
        },
      ),
    );

    return base.copyWith(
      // Aucun style ne porte de contour : les fonds sont opaques, le texte
      // n'a plus besoin d'être détouré pour rester lisible.
      textTheme: base.textTheme.copyWith(
        displaySmall: base.textTheme.displaySmall?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w900,
          letterSpacing: -.8,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w900,
          letterSpacing: -.5,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -.3,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          color: textPrimary,
          fontSize: 18,
          height: 1.2,
          fontWeight: FontWeight.w800,
          letterSpacing: -.2,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          color: textPrimary,
          fontSize: 15,
          height: 1.25,
          fontWeight: FontWeight.w700,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          color: textPrimary,
          fontSize: 13.5,
          height: 1.3,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          color: textPrimary,
          fontSize: 14,
          height: 1.5,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          color: textSecondary,
          fontSize: 13.5,
          height: 1.5,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          color: textFaint,
          fontSize: 12.5,
          height: 1.45,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          color: textPrimary,
          fontSize: 13.5,
          fontWeight: FontWeight.w800,
          letterSpacing: .05,
        ),
        labelMedium: base.textTheme.labelMedium?.copyWith(
          color: textSecondary,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
        labelSmall: base.textTheme.labelSmall?.copyWith(
          color: textLabel,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceBar,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 60,
        titleSpacing: 12,
        actionsPadding: EdgeInsets.only(right: 6),
        titleTextStyle: TextStyle(
          fontFamily: AppTypography.ui,
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: Colors.black.withValues(alpha: .18),
        shape: cardShape(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStateProperty.all(const Size(64, 48)),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return surfaceHigh;
            if (states.contains(WidgetState.pressed)) return primaryPressed;
            return primary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.disabled)
                ? textDisabled
                : Colors.white;
          }),
          overlayColor: WidgetStateProperty.all(
            Colors.white.withValues(alpha: .06),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusSm),
            ),
          ),
          textStyle: WidgetStateProperty.all(
            const TextStyle(
              fontFamily: AppTypography.ui,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          side: const BorderSide(color: outlineMarked),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          textStyle: const TextStyle(
            fontFamily: AppTypography.ui,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryBright,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: const TextStyle(
            fontFamily: AppTypography.ui,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      iconTheme: const IconThemeData(color: textSecondary, size: 22),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 13,
        ),
        hintStyle: const TextStyle(color: textFaint),
        labelStyle: const TextStyle(color: textSecondary),
        helperStyle: const TextStyle(
          color: textFaint,
          fontSize: 12,
          height: 1.35,
        ),
        errorStyle: const TextStyle(color: error, fontSize: 12, height: 1.35),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: outlineMarked),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: primaryBright, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: error, width: 1.4),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          // Les onglets principaux doivent rester lisibles sur téléphone,
          // y compris lorsque la fiche du match en affiche cinq côte à côte.
          minimumSize: WidgetStateProperty.all(const Size(48, 42)),
          textStyle: WidgetStateProperty.all(
            const TextStyle(
              fontFamily: AppTypography.ui,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? surfaceHero
                : surfaceHigh;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? Colors.white
                : textLabel;
          }),
          side: WidgetStateProperty.all(BorderSide.none),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusXs),
            ),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceHigh,
        side: const BorderSide(color: outline),
        labelStyle: const TextStyle(
          fontFamily: AppTypography.ui,
          color: textPrimary,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 62,
        backgroundColor: surfaceBarLow,
        indicatorColor: accent.withValues(alpha: .13),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: selected ? 25 : 21,
            color: selected ? accent : textLabelDim,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: AppTypography.ui,
            fontSize: selected ? 11.5 : 11,
            height: 1.1,
            color: selected ? Colors.white : textLabelDim,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          );
        }),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHero,
        contentTextStyle: const TextStyle(
          fontFamily: AppTypography.ui,
          color: textPrimary,
        ),
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
        circularTrackColor: progressTrack,
        linearTrackColor: progressTrack,
        linearMinHeight: 2,
        // Le tirer-pour-rafraîchir garde son geste : seule sa pastille
        // reprend les couleurs du fil de progression.
        refreshBackgroundColor: surface,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 1,
      ),
      dividerTheme: const DividerThemeData(
        color: outline,
        space: 24,
        thickness: 1,
      ),
      dividerColor: outline,
    );
  }
}
