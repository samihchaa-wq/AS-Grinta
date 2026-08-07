import 'package:as_grinta/core/widgets/grinta_app_background.dart';
import 'package:flutter/material.dart';

/// Fond de démarrage affiché avant que l'application complète soit montée.
///
/// Il réutilise exactement la même DA que l'application afin d'éviter un
/// flash d'ancien branding pendant l'initialisation Supabase.
class GrintaBackground extends StatelessWidget {
  const GrintaBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const GrintaAppBackground(),
        child,
      ],
    );
  }
}
