import 'package:as_grinta/core/widgets/collapsible_section_card.dart';
import 'package:as_grinta/features/matches/data/match_info_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_sport_report_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_goal_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Une ligne de la chronologie affichée dans la fiche du match.
class _FactRow {
  const _FactRow({
    required this.minuteLabel,
    required this.scorerLabel,
    required this.assistLabel,
    required this.scoreLabel,
    required this.isAwayGoal,
  });

  final String minuteLabel;

  /// Buteur, ou à défaut la nature du but (« But adverse », « CSC adverse »).
  final String scorerLabel;

  /// Passeur décisif, s'il est connu.
  final String? assistLabel;

  /// Score cumulé après ce but, dans l'ordre domicile – extérieur.
  final String scoreLabel;

  /// Les buts de l'équipe qui reçoit sont à gauche, ceux de l'équipe qui se
  /// déplace à droite, comme dans l'en-tête de la fiche.
  final bool isAwayGoal;
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
    final grintaIsHome =
        ref.watch(matchCoreProvider(matchId)).valueOrNull?.grintaIsHome ?? true;
    final rows = _buildRows(goals ?? const [], grintaIsHome: grintaIsHome);
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
  List<_FactRow> _buildRows(
    List<MatchGoalAction> goals, {
    required bool grintaIsHome,
  }) {
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
          scoreLabel: grintaIsHome
              ? '$scoreAsGrinta - $scoreAdverse'
              : '$scoreAdverse - $scoreAsGrinta',
          isAwayGoal: goal.isAsGrinta != grintaIsHome,
          scorerLabel: _scorerLabel(goal),
          assistLabel: goal.isAsGrinta &&
                  !goal.isOwnGoal &&
                  goal.assistKind == MatchGoalAssistKind.player
              ? goal.assistName
              : null,
        ),
      );
    }
    return rows;
  }

  String _scorerLabel(MatchGoalAction goal) {
    if (!goal.isAsGrinta) {
      return goal.isOwnGoal ? 'CSC AS Grinta' : 'But adverse';
    }
    if (goal.isOwnGoal) return 'CSC adverse';
    return goal.scorerName ?? 'But AS Grinta';
  }
}

/// Une ligne à la manière des sites de résultats : la minute au bord, la
/// pastille du score juste à côté, puis le buteur en gras et son passeur
/// entre parenthèses. Les buts de l'équipe qui reçoit partent de la gauche,
/// ceux de l'équipe qui se déplace de la droite, en miroir.
class _FactLine extends StatelessWidget {
  const _FactLine({required this.row});

  final _FactRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAway = row.isAwayGoal;
    final muted = theme.colorScheme.onSurfaceVariant;

    final minute = SizedBox(
      width: 34,
      child: Text(
        row.minuteLabel,
        textAlign: isAway ? TextAlign.right : TextAlign.left,
        style: theme.textTheme.bodyMedium?.copyWith(color: muted),
      ),
    );

    final scorePill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isAway) ...[
            const Icon(Icons.sports_soccer_rounded, size: 16),
            const SizedBox(width: 6),
          ],
          Text(
            row.scoreLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (isAway) ...[
            const SizedBox(width: 6),
            const Icon(Icons.sports_soccer_rounded, size: 16),
          ],
        ],
      ),
    );

    final scorer = TextSpan(
      text: row.scorerLabel,
      style: const TextStyle(fontWeight: FontWeight.w700),
    );
    final assist = row.assistLabel == null
        ? null
        : TextSpan(
            text: '(${row.assistLabel})',
            style: TextStyle(color: muted),
          );
    final label = Expanded(
      child: Text.rich(
        TextSpan(
          style: theme.textTheme.bodyMedium,
          children: isAway
              ? [
                  if (assist != null) ...[assist, const TextSpan(text: ' ')],
                  scorer,
                ]
              : [
                  scorer,
                  if (assist != null) ...[const TextSpan(text: ' '), assist],
                ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: isAway ? TextAlign.right : TextAlign.left,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: isAway
            ? [label, const SizedBox(width: 10), scorePill, minute]
            : [minute, scorePill, const SizedBox(width: 10), label],
      ),
    );
  }
}
