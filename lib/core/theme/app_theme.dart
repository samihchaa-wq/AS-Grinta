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
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(.025, .015),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

abstract final class AppTheme {
  // Palette principale
  static const Color background = Color(0xFF030A18);
  static const Color surface = Color(0xFF0B1830);
  static const Color surfaceHigh = Color(0xFF122443);
  static const Color surfaceHero = Color(0xFF172E56);
  static const Color outline = Color(0xFF29456D);
  static const Color primary = Color(0xFF3478F6);
  static const Color primaryBright = Color(0xFF72A8FF);
  static const Color accent = Color(0xFFFF4A8D);
  static const Color reward = Color(0xFFFFC857);
  static const Color success = Color(0xFF38C982);
  static const Color warning = Color(0xFFFF9F43);
  static const Color textPrimary = Color(0xFFF4F7FC);
  static const Color textSecondary = Color(0xFFC8D0DE);
  static const Color textFaint = Color(0xFF929EAF);

  // Grille visuelle commune
  static const double spaceXs = 8;
  static const double spaceSm = 12;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double radiusSm = 14;
  static const double radiusMd = 18;
  static const double radiusLg = 22;

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: surfaceHero,
      onPrimaryContainer: textPrimary,
      secondary: accent,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFF3B152D),
      onSecondaryContainer: Color(0xFFFFD9E8),
      tertiary: reward,
      onTertiary: background,
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      surfaceContainerHighest: surfaceHigh,
      error: Color(0xFFFF6B78),
      onError: Colors.white,
      outline: outline,
      outlineVariant: Color(0xFF1D3557),
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
          letterSpacing: -1.2,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -.7,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w800,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -.25,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          color: textPrimary,
          height: 1.42,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          color: textSecondary,
          height: 1.42,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          color: textFaint,
          height: 1.35,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: .1,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        toolbarHeight: 72,
        titleSpacing: 16,
        actionsPadding: EdgeInsets.only(right: 8),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 21,
          fontWeight: FontWeight.w800,
          letterSpacing: -.4,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface.withValues(alpha: .88),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: Colors.black.withValues(alpha: .2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: outline.withValues(alpha: .34)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: surfaceHigh,
          disabledForegroundColor: textFaint,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: BorderSide(color: outline.withValues(alpha: .72)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryBright,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconTheme: const IconThemeData(color: textSecondary, size: 22),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh.withValues(alpha: .82),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: const TextStyle(color: textFaint),
        labelStyle: const TextStyle(color: textSecondary),
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
          borderSide: const BorderSide(color: primaryBright, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: Color(0xFFFF6B78)),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? primary.withValues(alpha: .92)
                : surfaceHigh.withValues(alpha: .7);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? Colors.white
                : textSecondary;
          }),
          side: WidgetStateProperty.all(BorderSide.none),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceHigh.withValues(alpha: .8),
        side: BorderSide(color: outline.withValues(alpha: .32)),
        labelStyle: const TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: const Color(0xE60A1730),
        indicatorColor: primary.withValues(alpha: .22),
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: selected ? 25 : 23,
            color: selected ? primaryBright : textFaint,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            height: 1.1,
            color: selected ? textPrimary : textFaint,
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
        contentTextStyle: const TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryBright,
        circularTrackColor: surfaceHigh,
        linearTrackColor: surfaceHigh,
        linearMinHeight: 4,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      dividerTheme: DividerThemeData(
        color: outline.withValues(alpha: .38),
        space: 24,
        thickness: 1,
      ),
      dividerColor: outline.withValues(alpha: .38),
    );
  }
}
