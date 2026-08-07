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
  // Palette du blason AS La Grinta : bleu nuit, bleu royal, jaune club et blanc.
  static const Color background = Color(0xFF041224);
  static const Color surface = Color(0xFF091B33);
  static const Color surfaceHigh = Color(0xFF102A4A);
  static const Color surfaceHero = Color(0xFF173D6E);
  static const Color outline = Color(0xFF2A527E);
  static const Color primary = Color(0xFF3475C9);
  static const Color primaryBright = Color(0xFF67A9F3);
  static const Color accent = Color(0xFFFBE80C);
  static const Color reward = Color(0xFFFFD84A);
  static const Color success = Color(0xFF48C98B);
  static const Color warning = Color(0xFFF0A34A);
  static const Color admin = Color(0xFF5C9CE6);
  static const Color error = Color(0xFFFF6F7D);
  static const Color textPrimary = Color(0xFFF8FBFF);
  static const Color textSecondary = Color(0xFFDCE8F7);
  static const Color textFaint = Color(0xFF9FB4CC);

  // Très fin liseré noir appliqué au texte clair pour qu'il reste
  // net et lisible quel que soit ce qui se trouve derrière.
  static const List<Shadow> textOutline = [
    Shadow(offset: Offset(-.6, -.6), color: Colors.black),
    Shadow(offset: Offset(.6, -.6), color: Colors.black),
    Shadow(offset: Offset(-.6, .6), color: Colors.black),
    Shadow(offset: Offset(.6, .6), color: Colors.black),
  ];

  // Grille de 8 px et niveaux de surfaces communs.
  static const double spaceXs = 8;
  static const double spaceSm = 12;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double radiusSm = 12;
  static const double radiusMd = 16;
  static const double radiusLg = 22;

  static ShapeBorder cardShape({
    double radius = radiusMd,
    Color? borderColor,
    double borderWidth = 1,
  }) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(
          color: borderColor ?? outline.withValues(alpha: .34),
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
      onError: Colors.white,
      outline: outline,
      outlineVariant: Color(0xFF173755),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
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
      textTheme: base.textTheme.copyWith(
        displaySmall: base.textTheme.displaySmall?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
          shadows: textOutline,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -.55,
          shadows: textOutline,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w800,
          shadows: textOutline,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -.2,
          shadows: textOutline,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w700,
          shadows: textOutline,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          color: textPrimary,
          shadows: textOutline,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          color: textPrimary,
          height: 1.4,
          shadows: textOutline,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          color: textSecondary,
          height: 1.4,
          shadows: textOutline,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          color: textFaint,
          height: 1.35,
          shadows: textOutline,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: .05,
          shadows: textOutline,
        ),
        labelMedium: base.textTheme.labelMedium?.copyWith(
          color: textSecondary,
          shadows: textOutline,
        ),
        labelSmall: base.textTheme.labelSmall?.copyWith(
          color: textFaint,
          shadows: textOutline,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 60,
        titleSpacing: 12,
        actionsPadding: EdgeInsets.only(right: 6),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -.3,
          shadows: textOutline,
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
            if (states.contains(WidgetState.pressed)) {
              return primary.withValues(alpha: .78);
            }
            return primary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.disabled)
                ? textFaint
                : Colors.white;
          }),
          overlayColor: WidgetStateProperty.all(
            Colors.white.withValues(alpha: .06),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
          ),
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          side: BorderSide(color: outline.withValues(alpha: .6)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryBright,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
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
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: outline.withValues(alpha: .48)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: outline.withValues(alpha: .42)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: primaryBright, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: error, width: 1.4),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          // Les onglets principaux doivent rester lisibles sur téléphone,
          // y compris lorsque la fiche du match en affiche cinq côte à côte.
          minimumSize: WidgetStateProperty.all(const Size(48, 42)),
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? const Color(0xFF17457A)
                : surfaceHigh;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? primaryBright
                : textSecondary;
          }),
          side: WidgetStateProperty.all(BorderSide.none),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusSm),
            ),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceHigh,
        side: BorderSide(color: outline.withValues(alpha: .28)),
        labelStyle: const TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w700,
          shadows: textOutline,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 62,
        backgroundColor: const Color(0xFF07182D),
        indicatorColor: accent.withValues(alpha: .13),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: selected ? 25 : 21,
            color: selected ? accent : textFaint,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: selected ? 11.5 : 11,
            height: 1.1,
            color: selected ? textPrimary : textFaint,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            shadows: textOutline,
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
        contentTextStyle: const TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
        circularTrackColor: surfaceHigh,
        linearTrackColor: surfaceHigh,
        linearMinHeight: 4,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 1,
      ),
      dividerTheme: DividerThemeData(
        color: outline.withValues(alpha: .3),
        space: 24,
        thickness: 1,
      ),
      dividerColor: outline.withValues(alpha: .3),
    );
  }
}
