import 'package:flutter/widgets.dart';

/// Iconography foundations for Ma Petite Grinta.
///
/// Use one icon family per interface context and prefer outlined icons for
/// inactive actions. Filled variants are reserved for selected navigation,
/// confirmation and strong status communication.
abstract final class GrintaIconography {
  // Primitive sizes.
  static const double sizeXs = 14;
  static const double sizeSm = 18;
  static const double sizeMd = 22;
  static const double sizeLg = 26;
  static const double sizeXl = 32;
  static const double sizeDisplay = 40;

  // Semantic roles.
  static const double inline = sizeSm;
  static const double control = sizeMd;
  static const double navigation = sizeLg;
  static const double emptyState = sizeDisplay;

  // Touch targets remain larger than their visual icon.
  static const double compactTouchTarget = 40;
  static const double touchTarget = 48;

  static const BoxConstraints compactConstraints = BoxConstraints.tightFor(
    width: compactTouchTarget,
    height: compactTouchTarget,
  );

  static const BoxConstraints controlConstraints = BoxConstraints.tightFor(
    width: touchTarget,
    height: touchTarget,
  );
}
