import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Cadre responsive commun pour éviter les contenus trop étirés sur grand écran.
class GrintaResponsiveContent extends StatelessWidget {
  const GrintaResponsiveContent({
    super.key,
    required this.child,
    this.maxWidth = 1120,
    this.compact = false,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final bool compact;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final horizontal = switch (width) {
          < 480 => compact ? AppTheme.spaceSm : AppTheme.spaceMd,
          < 840 => AppTheme.spaceLg,
          _ => 32.0,
        };

        return Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontal),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Grille adaptative avec une largeur minimale stable pour chaque élément.
class GrintaResponsiveGrid extends StatelessWidget {
  const GrintaResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 280,
    this.spacing = AppTheme.spaceMd,
    this.runSpacing = AppTheme.spaceMd,
  });

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final count = ((available + spacing) / (minItemWidth + spacing))
            .floor()
            .clamp(1, children.length);
        final itemWidth = (available - spacing * (count - 1)) / count;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}
