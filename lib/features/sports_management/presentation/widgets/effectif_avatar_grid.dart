import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:flutter/material.dart';

/// Briques d'affichage de l'effectif d'un match, partagées par la page de
/// gestion des admins et l'onglet Effectif des joueurs.
///
/// Les deux écrans montrent les mêmes personnes : ils doivent les montrer de
/// la même façon (encadré coloré, photo à gauche du prénom, trois par ligne).
/// Seuls les gestes de gestion (glisser, relancer, retirer un invité) restent
/// propres aux admins, et passent par [EffectifSectionFrame.trailing],
/// [EffectifPlayerTile.onTap] et [EffectifPlayerTile.trailing].

/// Encadré d'une colonne d'effectif : « Convoqués », « Liste d'attente »…
class EffectifSectionFrame extends StatelessWidget {
  const EffectifSectionFrame({
    super.key,
    required this.title,
    required this.countLabel,
    required this.color,
    required this.icon,
    required this.child,
    this.highlighted = false,
    this.trailing,
  });

  final String title;

  /// Le nombre affiché après le titre, par exemple « 14 + coach ».
  final String countLabel;
  final Color color;
  final IconData icon;
  final Widget child;

  /// Vrai quand un joueur peut être déposé ici (admin seulement).
  final bool highlighted;

  /// Action placée à droite du titre (admin seulement).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      // Marges latérales serrées : sur un téléphone, les trois colonnes
      // laissent ainsi assez de place aux prénoms.
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 13),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: highlighted ? .20 : .11),
          Theme.of(context).colorScheme.surfaceContainer,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlighted ? color : color.withValues(alpha: .52),
          width: highlighted ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '$title ($countLabel)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w400,
                      ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// Texte d'une colonne vide.
class EffectifEmptyLabel extends StatelessWidget {
  const EffectifEmptyLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return Text('Aucun joueur.', style: Theme.of(context).textTheme.bodySmall);
  }
}

/// Grille de trois joueurs par ligne.
class EffectifAvatarGrid extends StatelessWidget {
  const EffectifAvatarGrid({super.key, required this.children});

  static const int columns = 3;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var row = 0; row < children.length; row += columns) ...[
          if (row > 0) const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < columns; column++) ...[
                if (column > 0) const SizedBox(width: 4),
                Expanded(
                  child: row + column < children.length
                      ? children[row + column]
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// Un joueur de l'effectif : sa photo (ou ses initiales) puis son prénom.
class EffectifPlayerTile extends StatelessWidget {
  const EffectifPlayerTile({
    super.key,
    required this.photoUrl,
    required this.name,
    required this.color,
    this.lastName,
    this.isGoalkeeper = false,
    this.isCoach = false,
    this.selected = false,
    this.selectionColor,
    this.onTap,
    this.trailing,
  });

  final String? photoUrl;
  final String name;
  final String? lastName;
  final bool isGoalkeeper;
  final bool isCoach;
  final Color color;
  final bool selected;

  /// Couleur du cadre quand le joueur est sélectionné (admin seulement).
  final Color? selectionColor;
  final VoidCallback? onTap;

  /// Petite action à droite du prénom (admin seulement). Le sifflet du coach
  /// passe avant elle.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final frameColor = selected ? (selectionColor ?? color) : color;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          constraints: const BoxConstraints(minHeight: 39),
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          decoration: BoxDecoration(
            color: selected
                ? frameColor.withValues(alpha: .16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: selected
                ? Border.all(color: frameColor.withValues(alpha: .85))
                : null,
          ),
          child: Row(
            children: [
              PlayerAvatar(
                photoUrl: photoUrl,
                name: name,
                lastName: lastName,
                isGoalkeeper: isGoalkeeper,
                size: 30,
                fallbackScale: .9,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              if (isCoach)
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Tooltip(
                    message:
                        'Coach : dans l’effectif, hors quota et hors composition',
                    child: Icon(Icons.sports_outlined, size: 14, color: color),
                  ),
                )
              else if (trailing != null)
                trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Dispose les colonnes d'effectif : deux par ligne sur grand écran (quatre
/// côte à côte coupaient les prénoms à deux ou trois lettres et le titre
/// « Sans réponse » lui-même), l'une sous l'autre sur téléphone.
class EffectifColumnsLayout extends StatelessWidget {
  const EffectifColumnsLayout({super.key, required this.columns});

  final List<Widget> columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Column(
            children: [
              for (var row = 0; row < columns.length; row += 2) ...[
                if (row > 0) const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: columns[row]),
                    if (row + 1 < columns.length) ...[
                      const SizedBox(width: 10),
                      Expanded(child: columns[row + 1]),
                    ],
                  ],
                ),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var index = 0; index < columns.length; index += 1) ...[
              columns[index],
              if (index < columns.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}
