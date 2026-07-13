import 'dart:ui' show FontFeature;

import 'package:as_grinta/core/design_system/foundations/grinta_colors.dart';
import 'package:flutter/material.dart';

/// Semantic typography foundations for Ma Petite Grinta.
///
/// The system deliberately uses the native platform typeface. This preserves
/// excellent rendering, accessibility and long-term stability without adding
/// a visual dependency or loading a remote font at runtime.
abstract final class GrintaTypography {
  static const List<String> _fallbacks = [
    'SF Pro Display',
    'SF Pro Text',
    'Inter',
    'Roboto',
  ];

  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
  ];

  /// Complete application type scale.
  ///
  /// Display and headline styles are compact and slightly tightened. Body
  /// styles preserve comfortable reading rhythm. Labels remain restrained so
  /// controls do not compete with the content hierarchy.
  static const TextTheme darkTextTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: 44,
      height: 1.09,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.4,
      color: GrintaColors.contentPrimary,
      fontFamilyFallback: _fallbacks,
    ),
    displayMedium: TextStyle(
      fontSize: 36,
      height: 1.11,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.1,
      color: GrintaColors.contentPrimary,
      fontFamilyFallback: _fallbacks,
    ),
    displaySmall: TextStyle(
      fontSize: 32,
      height: 1.13,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.9,
      color: GrintaColors.contentPrimary,
      fontFamilyFallback: _fallbacks,
    ),
    headlineLarge: TextStyle(
      fontSize: 28,
      height: 1.21,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.7,
      color: GrintaColors.contentPrimary,
      fontFamilyFallback: _fallbacks,
    ),
    headlineMedium: TextStyle(
      fontSize: 24,
      height: 1.25,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      color: GrintaColors.contentPrimary,
      fontFamilyFallback: _fallbacks,
    ),
    headlineSmall: TextStyle(
      fontSize: 21,
      height: 1.29,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      color: GrintaColors.contentPrimary,
      fontFamilyFallback: _fallbacks,
    ),
    titleLarge: TextStyle(
      fontSize: 18,
      height: 1.33,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      color: GrintaColors.contentPrimary,
      fontFamilyFallback: _fallbacks,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      height: 1.38,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      color: GrintaColors.contentPrimary,
      fontFamilyFallback: _fallbacks,
    ),
    titleSmall: TextStyle(
      fontSize: 14,
      height: 1.43,
      fontWeight: FontWeight.w600,
      color: GrintaColors.contentPrimary,
      fontFamilyFallback: _fallbacks,
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: GrintaColors.contentPrimary,
      fontFamilyFallback: _fallbacks,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: GrintaColors.contentSecondary,
      fontFamilyFallback: _fallbacks,
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: GrintaColors.contentSecondary,
      fontFamilyFallback: _fallbacks,
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      height: 1.43,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
      color: GrintaColors.contentPrimary,
      fontFamilyFallback: _fallbacks,
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      height: 1.33,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
      color: GrintaColors.contentSecondary,
      fontFamilyFallback: _fallbacks,
    ),
    labelSmall: TextStyle(
      fontSize: 11,
      height: 1.27,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      color: GrintaColors.contentTertiary,
      fontFamilyFallback: _fallbacks,
    ),
  );

  // Semantic styles not represented directly by Material's TextTheme.

  /// Large score, ranking or key statistical value.
  static const TextStyle score = TextStyle(
    fontSize: 40,
    height: 1,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.2,
    color: GrintaColors.contentPrimary,
    fontFamilyFallback: _fallbacks,
    fontFeatures: tabularFigures,
  );

  /// Compact numerical value used in tables, gauges and summary cards.
  static const TextStyle statistic = TextStyle(
    fontSize: 18,
    height: 1.22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: GrintaColors.contentPrimary,
    fontFamilyFallback: _fallbacks,
    fontFeatures: tabularFigures,
  );

  /// Quiet uppercase-style metadata such as status and section eyebrows.
  /// Text casing remains the responsibility of localized copy.
  static const TextStyle eyebrow = TextStyle(
    fontSize: 11,
    height: 1.27,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
    color: GrintaColors.contentTertiary,
    fontFamilyFallback: _fallbacks,
  );
}
