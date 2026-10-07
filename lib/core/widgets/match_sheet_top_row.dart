import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Haut d'une fiche de match : la flèche retour, puis le bandeau du match
/// juste à sa droite.
///
/// Les fiches n'ont pas de barre supérieure : ni écusson, ni titre, ni bouton
/// d'actualisation (tirer l'écran vers le bas recharge la fiche). Le bandeau
/// prend donc toute la hauteur libérée en haut de l'écran. Sans bandeau
/// (chargement, Live plein écran, aucun match), la flèche reste seule.
class MatchSheetTopRow extends StatelessWidget {
  const MatchSheetTopRow({
    super.key,
    this.header,
    this.bottomSpacing = 16,
  });

  /// Bandeau du match, ou null pour n'afficher que la flèche.
  final Widget? header;

  /// Espace sous la ligne, avant le reste de la fiche.
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    final header = this.header;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const MatchSheetBackButton(),
          if (header != null) ...[
            const SizedBox(width: 4),
            Expanded(child: header),
          ],
        ],
      ),
    );
  }
}

/// Flèche retour des fiches de match.
///
/// Revient à l'écran précédent. Ouverte sans écran précédent (lien direct),
/// elle ramène au calendrier plutôt que de ne rien faire.
class MatchSheetBackButton extends StatelessWidget {
  const MatchSheetBackButton({super.key});

  static const double width = 40;

  @override
  Widget build(BuildContext context) {
    return BackButton(
      style: IconButton.styleFrom(
        minimumSize: const Size(width, kMinInteractiveDimension),
        maximumSize: const Size(width, kMinInteractiveDimension),
        padding: EdgeInsets.zero,
      ),
      onPressed: () {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
        } else {
          context.go('/matches');
        }
      },
    );
  }
}
