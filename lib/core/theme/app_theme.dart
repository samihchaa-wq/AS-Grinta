import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const Color primary = Color(0xFF1658D6);
  static const Color accent = Color(0xFFFF3F8E);
  static const Color background = Color(0xFF08152F);
  static const Color surface = Color(0xFF10224A);
  static const Color surfaceHigh = Color(0xFF173266);
  static const Color outline = Color(0xFF29477E);

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: primary,
      onPrimary: Colors.white,
      secondary: accent,
      onSecondary: Colors.white,
      surface: surface,
      onSurface: Color(0xFFF8FAFF),
      error: Color(0xFFFF6B7A),
      onError: Colors.white,
      outline: outline,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displaySmall: base.textTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1.4,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          color: const Color(0xFFE7EDFA),
          height: 1.4,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          color: const Color(0xFFB8C6E3),
          height: 1.4,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: primary.withValues(alpha: 0.16),
        side: BorderSide(color: primary.withValues(alpha: 0.40)),
        labelStyle: const TextStyle(
          color: Color(0xFFDCE7FF),
          fontWeight: FontWeight.w800,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 74,
        backgroundColor: const Color(0xFF0C1C3C),
        indicatorColor: primary,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? Colors.white : const Color(0xFF91A2C5),
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          );
        }),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: accent),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      dividerColor: outline,
    );
  }
}
