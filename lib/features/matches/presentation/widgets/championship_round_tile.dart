import 'package:as_grinta/features/matches/domain/championship_round.dart';
import 'package:flutter/material.dart';

/// Choix de la journée de championnat d'une rencontre.
///
/// Le numéro vient du calendrier de la ligue : l'application propose la
/// journée suivante de la saison, l'administrateur la corrige quand le club
/// saute une journée ou saisit le calendrier dans le désordre.
class ChampionshipRoundTile extends StatelessWidget {
  const ChampionshipRoundTile({
    required this.round,
    required this.roundsOfSeason,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final int? round;
  final List<int?> roundsOfSeason;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final current = round;
    final duplicated = current != null &&
        championshipRoundIsAlreadyUsed(
          round: current,
          roundsOfSeason: roundsOfSeason,
        );

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.format_list_numbered_rounded),
      title: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          current == null
              ? 'Journée de championnat · Numéro automatique'
              : duplicated
                  ? 'Journée de championnat J$current · déjà utilisée cette saison'
                  : 'Journée de championnat J$current',
          maxLines: 1,
          style: duplicated
              ? TextStyle(color: Theme.of(context).colorScheme.error)
              : null,
        ),
      ),
      trailing: const Icon(Icons.unfold_more_rounded),
      onTap: enabled ? onTap : null,
    );
  }
}
