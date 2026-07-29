import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Dispose les champs sur une ou deux colonnes selon l'espace disponible.
class GrintaAdaptiveForm extends StatelessWidget {
  const GrintaAdaptiveForm({
    required this.children,
    super.key,
    this.breakpoint = 720,
    this.spacing = AppTheme.spaceMd,
    this.runSpacing = AppTheme.spaceMd,
  });

  final List<Widget> children;
  final double breakpoint;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= breakpoint ? 2 : 1;
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - spacing) / 2;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}
