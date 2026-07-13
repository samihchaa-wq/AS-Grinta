import 'package:as_grinta/core/design_system/foundations/grinta_colors.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_elevation.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_radii.dart';
import 'package:flutter/material.dart';

/// Visual hierarchy available to reusable surfaces.
enum GrintaSurfaceLevel { base, raised, elevated, emphasis }

/// Shared surface primitive for cards, panels and grouped content.
///
/// This component centralizes surface color, border, radius and depth so
/// feature screens do not create independent container styles.
class GrintaSurface extends StatelessWidget {
  const GrintaSurface({
    required this.child,
    super.key,
    this.level = GrintaSurfaceLevel.raised,
    this.padding,
    this.margin,
    this.borderRadius = GrintaRadii.cardRadius,
    this.showBorder = true,
    this.shadow = GrintaElevation.none,
    this.clipBehavior = Clip.none,
  });

  final Widget child;
  final GrintaSurfaceLevel level;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadiusGeometry borderRadius;
  final bool showBorder;
  final List<BoxShadow> shadow;
  final Clip clipBehavior;

  Color get _backgroundColor {
    return switch (level) {
      GrintaSurfaceLevel.base => GrintaColors.surfaceBase,
      GrintaSurfaceLevel.raised => GrintaColors.surfaceRaised,
      GrintaSurfaceLevel.elevated => GrintaColors.surfaceElevated,
      GrintaSurfaceLevel.emphasis => GrintaColors.surfaceEmphasis,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: borderRadius,
        border: showBorder
            ? Border.all(color: GrintaColors.borderSubtle)
            : null,
        boxShadow: shadow,
      ),
      clipBehavior: clipBehavior,
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
  }
}
