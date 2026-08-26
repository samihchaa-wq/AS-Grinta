import 'package:flutter/material.dart';

/// Ancien composant d'aperçu de chargement.
///
/// Conservé uniquement pour compatibilité avec les appels existants. Aucun
/// squelette ni animation n'est rendu : après le démarrage de l'application,
/// aucun loader visuel ne doit apparaître.
class GrintaSkeleton extends StatelessWidget {
  const GrintaSkeleton({super.key, required this.child});

  const GrintaSkeleton.list({
    super.key,
    int itemCount = 4,
    double itemHeight = 96,
    double spacing = 12,
  }) : child = const SizedBox.shrink();

  const GrintaSkeleton.rows({super.key, int itemCount = 6})
    : child = const SizedBox.shrink();

  final Widget child;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
