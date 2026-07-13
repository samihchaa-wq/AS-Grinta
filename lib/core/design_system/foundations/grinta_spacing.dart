import 'package:flutter/widgets.dart';

/// Spacing and layout foundations for Ma Petite Grinta.
///
/// The scale follows a compact 4-point grid. Components and screens should use
/// these semantic roles instead of introducing isolated numeric values.
abstract final class GrintaSpacing {
  // Primitive 4-point scale.
  static const double space0 = 0;
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;
  static const double space10 = 40;
  static const double space12 = 48;
  static const double space16 = 64;
  static const double space20 = 80;

  // Semantic component spacing.
  static const double iconGap = space2;
  static const double inlineGap = space3;
  static const double controlGap = space3;
  static const double contentGap = space4;
  static const double sectionGap = space6;
  static const double majorSectionGap = space8;

  // Semantic insets.
  static const double controlInsetHorizontal = space4;
  static const double controlInsetVertical = space3;
  static const double cardInset = space5;
  static const double compactCardInset = space4;
  static const double dialogInset = space6;

  // Screen layout.
  static const double screenHorizontal = space5;
  static const double screenTop = space4;
  static const double screenBottom = space8;
  static const double contentMaxWidth = 720;

  static const EdgeInsets screenInsets = EdgeInsets.fromLTRB(
    screenHorizontal,
    screenTop,
    screenHorizontal,
    screenBottom,
  );

  static const EdgeInsets cardInsets = EdgeInsets.all(cardInset);
  static const EdgeInsets compactCardInsets = EdgeInsets.all(compactCardInset);
  static const EdgeInsets controlInsets = EdgeInsets.symmetric(
    horizontal: controlInsetHorizontal,
    vertical: controlInsetVertical,
  );
}
