import 'package:as_grinta/core/design_system/foundations/grinta_colors.dart';
import 'package:flutter/widgets.dart';

/// Depth foundations for Ma Petite Grinta.
///
/// Depth is created primarily through surface contrast and borders. Shadows
/// are subtle and reserved for floating or modal elements.
abstract final class GrintaElevation {
  static const double flat = 0;
  static const double raised = 1;
  static const double floating = 8;
  static const double modal = 16;

  static const List<BoxShadow> none = [];

  static const List<BoxShadow> raisedShadow = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> floatingShadow = [
    BoxShadow(
      color: Color(0x33000000),
      blurRadius: 24,
      offset: Offset(0, 10),
    ),
  ];

  static const List<BoxShadow> modalShadow = [
    BoxShadow(
      color: Color(0x52000000),
      blurRadius: 40,
      offset: Offset(0, 18),
    ),
  ];

  static const Border subtleBorder = Border.fromBorderSide(
    BorderSide(color: GrintaColors.borderSubtle),
  );

  static const Border defaultBorder = Border.fromBorderSide(
    BorderSide(color: GrintaColors.borderDefault),
  );
}
