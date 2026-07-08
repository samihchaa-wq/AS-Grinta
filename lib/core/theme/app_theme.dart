import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const Color primary = Color(0xFF1F77D2);
  static const Color accent = Color(0xFFFF8A2A);
  static const Color background = Color(0xFF0E141B);
  static const Color surface = Color(0xFF17212B);

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
      surface: surface,
    ).copyWith(secondary: accent);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: 0.25),
      ),
      cardTheme: const CardThemeData(color: surface),
    );
  }
}
