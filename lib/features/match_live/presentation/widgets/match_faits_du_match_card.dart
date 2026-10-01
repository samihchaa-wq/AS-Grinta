import 'package:as_grinta/core/widgets/collapsible_section_card.dart';
import 'package:as_grinta/features/sports_management/data/match_sport_report_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_goal_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Une ligne de la chronologie affichée dans la fiche du match.
class _FactRow {
  const _FactRow({
    required this.minuteLabel,
    required this.text,
    required this.scoreLabel,
    required this.isAsGrintaGoal,
  });

  final String minuteLabel;
  final String text;

  /// Score cumulé après ce but.
  final String scoreLabel;
  final bool isAsGrintaGoal;
}

/// Chronologie des buts d'un match terminé, dans sa fiche.
///
/// Les buts viennent du **compte rendu validé** : c'est la version corrigée par
/// l'administrateur, pas le brouillon saisi en direct. Corriger un buteur ou
/// une minute dans le compte rendu se voit donc immédiatement ici, et un match
/// saisi sans suivi en direct a lui aussi sa chronologie.
///
/// Les remplacements n'y figurent pas : une fois le match fini, seuls les buts
/// intéressent la fiche.
class MatchFaitsDuMatchCard extends ConsumerWidget {
  const MatchFaitsDuMatchCard({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(matchGoalActionsProvider(matchId)).valueOrNull;
    final rows = _buildRows(goals ?? const []);
    if (rows.isEmpty) return const SizedBox.shrink();

    return CollapsibleSectionCard(
      storageKey: 'match-$matchId-faits',
      icon: Icons.timeline_rounded,
      title: 'Faits du match',
      children: [
        for (final row in rows) _FactLine(row: row),
        const SizedBox(height: 8),
      ],
    );
  }

  /// Les buts arrivent déjà dans l'ordre retenu par le compte rendu : le score
  /// cumulé se reconstitue simplement en les parcourant.
  List<_FactRow> _buildRows(List<MatchGoalAction> goals) {
    var scoreAsGrinta = 0;
    var scoreAdverse = 0;
    final rows = <_FactRow>[];
    for (final goal in goals) {
      if (goal.isAsGrinta) {
        scoreAsGrinta += 1;
      } else {
        scoreAdverse += 1;
      }
      rows.add(
        _FactRow(
          minuteLabel: goal.minute == null ? '—' : "${goal.minute}'",
          scoreLabel: '$scoreAsGrinta-$scoreAdverse',
          isAsGrintaGoal: goal.isAsGrinta,
          text: _goalText(goal),
        ),
      );
    }
    return rows;
  }

  String _goalText(MatchGoalAction goal) {
    if (!goal.isAsGrinta) {
      return goal.isOwnGoal ? 'CSC AS Grinta' : 'But adverse';
    }
    if (goal.isOwnGoal) return 'CSC adverse';
    final scorer = goal.scorerName ?? 'But AS Grinta';
    return goal.assistKind == MatchGoalAssistKind.player
        ? '$scorer (passe ${goal.assistName})'
        : scorer;
  }
}

class _FactLine extends StatelessWidget {
  const _FactLine({required this.row});

  final _FactRow row;

  @override
  Widget build(BuildContext context) {
    final isOpponentGoal = !row.isAsGrintaGoal;
    final goalIndent =
        (MediaQuery.sizeOf(context).width * .12).clamp(36.0, 64.0).toDouble();
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Align(
                  alignment: isOpponentGoal
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: isOpponentGoal ? 0 : goalIndent,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(Icons.sports_soccer_rounded, size: 20),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * .58,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: isOpponentGoal
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: isOpponentGoal
                                    ? TextAlign.right
                                    : TextAlign.left,
                              ),
                              Text(
                                row.scoreLabel,
                                textAlign: isOpponentGoal
                                    ? TextAlign.right
                                    : TextAlign.left,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                row.minuteLabel,
                style: const TextStyle(fontWeight: FontWeight.w400),
              ),
            ],
          ),
        );
      },
    );
  }
}
