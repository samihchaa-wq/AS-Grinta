import 'package:flutter/widgets.dart';

/// Corner-radius foundations for Ma Petite Grinta.
///
/// The scale is intentionally restrained. Large radii are reserved for major
/// surfaces; controls use tighter radii to avoid a generic "bubble UI" look.
abstract final class GrintaRadii {
  // Primitive scale.
  static const double none = 0;
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double full = 999;

  // Semantic roles.
  static const double control = md;
  static const double field = md;
  static const double card = lg;
  static const double prominentCard = xl;
  static const double dialog = xl;
  static const double sheet = xl;
  static const double badge = full;

  static const BorderRadius controlRadius = BorderRadius.all(
    Radius.circular(control),
  );
  static const BorderRadius fieldRadius = BorderRadius.all(
    Radius.circular(field),
  );
  static const BorderRadius cardRadius = BorderRadius.all(
    Radius.circular(card),
  );
  static const BorderRadius prominentCardRadius = BorderRadius.all(
    Radius.circular(prominentCard),
  );
  static const BorderRadius dialogRadius = BorderRadius.all(
    Radius.circular(dialog),
  );
  static const BorderRadius badgeRadius = BorderRadius.all(
    Radius.circular(badge),
  );
}
