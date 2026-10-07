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

/// Liste défilante d'une fiche de match.
///
/// Comme un [ListView], sauf que la marge gauche de [padding] ne s'applique
/// pas aux [MatchSheetTopRow] : leur flèche retour se colle au bord gauche de
/// l'écran au lieu de s'aligner sur le contenu. La marge est posée enfant par
/// enfant plutôt que sur la liste, sinon la zone tactile de la flèche serait
/// coupée par la marge.
class MatchSheetListView extends StatelessWidget {
  const MatchSheetListView({
    super.key,
    required this.padding,
    required this.children,
    this.physics,
  });

  final EdgeInsets padding;
  final List<Widget> children;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: physics,
      padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
      children: [
        for (final child in children)
          Padding(
            padding: EdgeInsets.only(
              left: child is MatchSheetTopRow ? 0 : padding.left,
              right: padding.right,
            ),
            child: child,
          ),
      ],
    );
  }
}

/// Flèche retour des fiches de match, collée au bord gauche de l'écran.
///
/// Revient à l'écran précédent. Ouverte sans écran précédent (lien direct),
/// elle ramène au calendrier plutôt que de ne rien faire.
class MatchSheetBackButton extends StatelessWidget {
  const MatchSheetBackButton({super.key});

  static const double width = 36;

  /// Écart entre le bord de l'écran et la flèche.
  static const double edgeInset = 4;

  @override
  Widget build(BuildContext context) {
    return BackButton(
      style: IconButton.styleFrom(
        minimumSize: const Size(width, kMinInteractiveDimension),
        maximumSize: const Size(width, kMinInteractiveDimension),
        padding: const EdgeInsets.only(left: edgeInset),
        alignment: Alignment.centerLeft,
        // Sinon Flutter élargit le bouton à 48 et recentre la flèche.
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
