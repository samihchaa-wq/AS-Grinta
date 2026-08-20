import 'package:as_grinta/core/widgets/grinta_app_background.dart';
import 'package:flutter/material.dart';

/// Fond de démarrage affiché avant que l'application complète soit montée.
///
/// Le démarrage est, avec la connexion, le seul endroit où l'illustration du
/// club subsiste : une fois l'application montée, tous les écrans reposent sur
/// un fond plat.
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
