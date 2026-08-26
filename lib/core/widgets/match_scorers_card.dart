import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class MatchScorerEntry {
  const MatchScorerEntry({required this.name, required this.goals});

  final String name;
  final int goals;
}

/// Bloc « Buteurs » partagé par les matchs modernes et les archives importées.
///
/// L'absence de détail historique n'est jamais transformée en faux zéro : si
/// AS Grinta a marqué mais que la source ne donne aucun nom, le bloc l'indique
/// explicitement.
class MatchScorersCard extends StatelessWidget {
  const MatchScorersCard({
    super.key,
    required this.teamGoals,
    required this.scorers,
  });

  /// Nul uniquement lorsqu'une ancienne source ne permet pas de connaître le
  /// total au moment où la fiche est reconstruite.
  final int? teamGoals;
  final List<MatchScorerEntry> scorers;

  @override
  Widget build(BuildContext context) {
    final effectiveScorers = scorers
        .where((scorer) => scorer.goals > 0 && scorer.name.trim().isNotEmpty)
        .toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Buteurs',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            if (effectiveScorers.isEmpty)
              Text(
                teamGoals == 0 ? 'Aucun buteur' : 'Buteurs non renseignés',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
              )
            else
              ...effectiveScorers.map(
                (scorer) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.sports_soccer_rounded, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          scorer.name,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                      if (scorer.goals > 1)
                        Text(
                          '×${scorer.goals}',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
