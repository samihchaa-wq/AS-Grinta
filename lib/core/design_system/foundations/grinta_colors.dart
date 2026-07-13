import 'package:flutter/material.dart';

/// Color foundations for Ma Petite Grinta.
///
/// The palette is intentionally split into two layers:
/// - primitive colors are implementation details;
/// - semantic colors describe the role a color plays in the interface.
///
/// Screens and reusable components should consume semantic colors only.
abstract final class GrintaColors {
  // ---------------------------------------------------------------------------
  // Primitive palette
  // ---------------------------------------------------------------------------

  static const Color navy950 = Color(0xFF07101F);
  static const Color navy900 = Color(0xFF0B1628);
  static const Color navy850 = Color(0xFF101D31);
  static const Color navy800 = Color(0xFF16253A);
  static const Color navy700 = Color(0xFF22354E);
  static const Color navy600 = Color(0xFF334A68);

  static const Color slate500 = Color(0xFF74839A);
  static const Color slate400 = Color(0xFF98A5B8);
  static const Color slate300 = Color(0xFFBBC4D1);
  static const Color slate100 = Color(0xFFE8ECF2);
  static const Color slate50 = Color(0xFFF6F8FB);

  static const Color blue600 = Color(0xFF356FE5);
  static const Color blue500 = Color(0xFF4D83EE);
  static const Color blue300 = Color(0xFF8FB2F7);

  static const Color rose500 = Color(0xFFD95A87);
  static const Color rose300 = Color(0xFFF0A2BD);

  static const Color green500 = Color(0xFF3FA477);
  static const Color amber500 = Color(0xFFD29A3A);
  static const Color red500 = Color(0xFFD85D66);

  static const Color white = Color(0xFFFFFFFF);
  static const Color transparent = Color(0x00000000);

  // ---------------------------------------------------------------------------
  // Semantic surfaces
  // ---------------------------------------------------------------------------

  /// Main application canvas.
  static const Color surfaceBase = navy950;

  /// Default content surface, such as cards and navigation containers.
  static const Color surfaceRaised = navy900;

  /// Surface used to create a subtle hierarchy inside a raised surface.
  static const Color surfaceElevated = navy850;

  /// Selected, pressed or emphasized neutral surface.
  static const Color surfaceEmphasis = navy800;

  /// Scrim used behind dialogs and modal sheets.
  static const Color surfaceScrim = Color(0xB307101F);

  // ---------------------------------------------------------------------------
  // Semantic content
  // ---------------------------------------------------------------------------

  static const Color contentPrimary = slate50;
  static const Color contentSecondary = slate300;
  static const Color contentTertiary = slate400;
  static const Color contentDisabled = slate500;
  static const Color contentInverse = navy950;

  // ---------------------------------------------------------------------------
  // Semantic borders
  // ---------------------------------------------------------------------------

  static const Color borderSubtle = Color(0xFF1D2C42);
  static const Color borderDefault = navy700;
  static const Color borderStrong = navy600;

  // ---------------------------------------------------------------------------
  // Semantic actions and brand accents
  // ---------------------------------------------------------------------------

  /// Main action color. Use for primary calls to action and active navigation.
  static const Color actionPrimary = blue600;
  static const Color actionPrimaryHover = blue500;
  static const Color actionPrimaryContent = white;

  /// Secondary brand accent. Reserve for rare highlights, not general emphasis.
  static const Color accentPrimary = rose500;
  static const Color accentSoft = Color(0xFF351D2B);
  static const Color accentContent = rose300;

  /// Accessible brand content on dark surfaces.
  static const Color brandContent = blue300;

  // ---------------------------------------------------------------------------
  // Semantic statuses
  // ---------------------------------------------------------------------------

  static const Color statusSuccess = green500;
  static const Color statusWarning = amber500;
  static const Color statusDanger = red500;
  static const Color statusInfo = blue500;

  static const Color statusSuccessSoft = Color(0xFF132C25);
  static const Color statusWarningSoft = Color(0xFF302716);
  static const Color statusDangerSoft = Color(0xFF331D22);
  static const Color statusInfoSoft = Color(0xFF172A4B);

  // ---------------------------------------------------------------------------
  // Interaction overlays
  // ---------------------------------------------------------------------------

  static const Color overlayHover = Color(0x0FFFFFFF);
  static const Color overlayPressed = Color(0x18FFFFFF);
  static const Color overlayFocus = Color(0x24356FE5);
}
