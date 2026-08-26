import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Fond uni de démarrage affiché avant que l'application complète soit montée.
class GrintaBackground extends StatelessWidget {
  const GrintaBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: AppTheme.background, child: child);
  }
}
