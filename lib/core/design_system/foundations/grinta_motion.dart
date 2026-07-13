import 'package:flutter/animation.dart';

/// Motion foundations for Ma Petite Grinta.
///
/// Motion must clarify hierarchy and state changes. It should never delay an
/// action, decorate idle screens or compete with football data.
abstract final class GrintaMotion {
  // Durations.
  static const Duration instant = Duration(milliseconds: 0);
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration emphasized = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 400);

  // Curves.
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve standardCurve = Curves.easeInOutCubic;
  static const Curve emphasizedCurve = Curves.easeOutQuart;

  // Semantic roles.
  static const Duration stateChange = fast;
  static const Duration contentTransition = standard;
  static const Duration modalTransition = emphasized;
  static const Duration pageTransition = emphasized;

  static const Curve stateChangeCurve = standardCurve;
  static const Curve contentEnterCurve = enter;
  static const Curve contentExitCurve = exit;
  static const Curve modalCurve = emphasizedCurve;

  /// Maximum distance for subtle slide transitions.
  static const double shortTravel = 8;

  /// Maximum distance for modal and page entrances.
  static const double mediumTravel = 16;
}
