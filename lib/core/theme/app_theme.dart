import 'package:as_grinta/core/design_system/foundations/grinta_colors.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_elevation.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_radii.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_typography.dart';
import 'package:flutter/material.dart';

/// Application theme built from the semantic Design System foundations.
///
/// New UI code should use [Theme.of] and semantic Design System roles rather
/// than introducing literal visual values. The compatibility aliases below
/// remain temporarily available while existing screens are migrated.
abstract final class AppTheme {
  // Compatibility aliases. Do not add new aliases here.
  static const Color background = GrintaColors.surfaceBase;
  static const Color surface = GrintaColors.surfaceRaised;
  static const Color surfaceHigh = GrintaColors.surfaceElevated;
  static const Color outline = GrintaColors.borderDefault;
  static const Color primary = GrintaColors.actionPrimary;
  static const Color primaryBright = GrintaColors.brandContent;
  static const Color accent = GrintaColors.accentPrimary;
  static const Color textPrimary = GrintaColors.contentPrimary;
  static const Color textSecondary = GrintaColors.contentSecondary;
  static const Color textFaint = GrintaColors.contentTertiary;

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: GrintaColors.actionPrimary,
      onPrimary: GrintaColors.actionPrimaryContent,
      primaryContainer: GrintaColors.surfaceEmphasis,
      onPrimaryContainer: GrintaColors.contentPrimary,
      secondary: GrintaColors.accentPrimary,
      onSecondary: GrintaColors.white,
      secondaryContainer: GrintaColors.accentSoft,
      onSecondaryContainer: GrintaColors.accentContent,
      tertiary: GrintaColors.brandContent,
      onTertiary: GrintaColors.contentInverse,
      surface: GrintaColors.surfaceRaised,
      onSurface: GrintaColors.contentPrimary,
      onSurfaceVariant: GrintaColors.contentSecondary,
      surfaceContainerHighest: GrintaColors.surfaceElevated,
      error: GrintaColors.statusDanger,
      onError: GrintaColors.white,
      errorContainer: GrintaColors.statusDangerSoft,
      onErrorContainer: GrintaColors.contentPrimary,
      outline: GrintaColors.borderDefault,
      outlineVariant: GrintaColors.borderSubtle,
      scrim: GrintaColors.surfaceScrim,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      textTheme: GrintaTypography.darkTextTheme,
      primaryTextTheme: GrintaTypography.darkTextTheme,
      scaffoldBackgroundColor: GrintaColors.surfaceBase,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: GrintaColors.transparent,
        surfaceTintColor: GrintaColors.transparent,
        foregroundColor: GrintaColors.contentPrimary,
        elevation: GrintaElevation.flat,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 21,
          height: 1.29,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: GrintaColors.contentPrimary,
          fontFamilyFallback: [
            'SF Pro Display',
            'SF Pro Text',
            'Inter',
            'Roboto',
          ],
        ),
        iconTheme: IconThemeData(color: GrintaColors.contentPrimary),
      ),
      cardTheme: const CardThemeData(
        color: GrintaColors.surfaceRaised,
        elevation: GrintaElevation.flat,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: GrintaRadii.cardRadius,
          side: BorderSide(color: GrintaColors.borderDefault),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: GrintaColors.actionPrimary,
          foregroundColor: GrintaColors.actionPrimaryContent,
          disabledBackgroundColor: GrintaColors.surfaceElevated,
          disabledForegroundColor: GrintaColors.contentDisabled,
          minimumSize: const Size(64, 52),
          shape: const RoundedRectangleBorder(
            borderRadius: GrintaRadii.controlRadius,
          ),
          textStyle: GrintaTypography.darkTextTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: GrintaColors.contentPrimary,
          minimumSize: const Size(64, 52),
          side: const BorderSide(color: GrintaColors.borderDefault),
          shape: const RoundedRectangleBorder(
            borderRadius: GrintaRadii.controlRadius,
          ),
          textStyle: GrintaTypography.darkTextTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: GrintaColors.contentPrimary,
          textStyle: GrintaTypography.darkTextTheme.labelLarge,
        ),
      ),
      iconTheme: const IconThemeData(color: GrintaColors.contentSecondary),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: GrintaColors.surfaceElevated,
        hintStyle: GrintaTypography.darkTextTheme.bodyMedium?.copyWith(
          color: GrintaColors.contentTertiary,
        ),
        labelStyle: GrintaTypography.darkTextTheme.bodyMedium,
        floatingLabelStyle: GrintaTypography.darkTextTheme.labelMedium?.copyWith(
          color: GrintaColors.brandContent,
        ),
        border: const OutlineInputBorder(
          borderRadius: GrintaRadii.fieldRadius,
          borderSide: BorderSide(color: GrintaColors.borderDefault),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: GrintaRadii.fieldRadius,
          borderSide: BorderSide(color: GrintaColors.borderDefault),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: GrintaRadii.fieldRadius,
          borderSide: BorderSide(
            color: GrintaColors.accentPrimary,
            width: 1.6,
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? GrintaColors.actionPrimary
                : GrintaColors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? GrintaColors.actionPrimaryContent
                : GrintaColors.contentSecondary;
          }),
          textStyle: WidgetStateProperty.all(
            GrintaTypography.darkTextTheme.labelMedium,
          ),
          side: WidgetStateProperty.all(
            const BorderSide(color: GrintaColors.borderDefault),
          ),
          shape: WidgetStateProperty.all(
            const RoundedRectangleBorder(
              borderRadius: GrintaRadii.controlRadius,
            ),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: GrintaColors.surfaceElevated,
        side: const BorderSide(color: GrintaColors.borderDefault),
        labelStyle: GrintaTypography.darkTextTheme.labelMedium,
        shape: const RoundedRectangleBorder(
          borderRadius: GrintaRadii.badgeRadius,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 74,
        elevation: GrintaElevation.flat,
        backgroundColor: GrintaColors.surfaceRaised,
        indicatorColor: GrintaColors.actionPrimary,
        surfaceTintColor: GrintaColors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? GrintaColors.actionPrimaryContent
                : GrintaColors.contentSecondary,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GrintaTypography.darkTextTheme.labelSmall?.copyWith(
            color: selected
                ? GrintaColors.actionPrimaryContent
                : GrintaColors.contentSecondary,
          );
        }),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: GrintaColors.surfaceRaised,
        surfaceTintColor: GrintaColors.transparent,
        elevation: GrintaElevation.modal,
        shape: RoundedRectangleBorder(
          borderRadius: GrintaRadii.dialogRadius,
          side: BorderSide(color: GrintaColors.borderSubtle),
        ),
        titleTextStyle: TextStyle(
          fontSize: 21,
          height: 1.29,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: GrintaColors.contentPrimary,
          fontFamilyFallback: [
            'SF Pro Display',
            'SF Pro Text',
            'Inter',
            'Roboto',
          ],
        ),
        contentTextStyle: TextStyle(
          fontSize: 14,
          height: 1.5,
          fontWeight: FontWeight.w400,
          color: GrintaColors.contentSecondary,
          fontFamilyFallback: [
            'SF Pro Display',
            'SF Pro Text',
            'Inter',
            'Roboto',
          ],
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: GrintaColors.surfaceElevated,
        elevation: GrintaElevation.floating,
        shape: RoundedRectangleBorder(
          borderRadius: GrintaRadii.controlRadius,
          side: BorderSide(color: GrintaColors.borderSubtle),
        ),
        contentTextStyle: TextStyle(
          fontSize: 14,
          height: 1.5,
          fontWeight: FontWeight.w400,
          color: GrintaColors.contentPrimary,
          fontFamilyFallback: [
            'SF Pro Display',
            'SF Pro Text',
            'Inter',
            'Roboto',
          ],
        ),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: GrintaColors.accentPrimary,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: GrintaElevation.floating,
        backgroundColor: GrintaColors.accentPrimary,
        foregroundColor: GrintaColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: GrintaRadii.controlRadius,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: GrintaColors.borderSubtle,
      ),
      dividerColor: GrintaColors.borderSubtle,
    );
  }
}
