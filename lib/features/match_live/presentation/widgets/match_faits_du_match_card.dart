import 'package:as_grinta/features/match_live/domain/match_live_event.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/live_substitution_line.dart';
import 'package:as_grinta/features/sports_management/data/match_sport_report_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_goal_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Une ligne de la chronologie affichée dans la fiche du match.
class _FactRow {
  const _FactRow({
    required this.minuteLabel,
    required this.text,
    required this.icon,
    required this.order,
    this.scoreLabel,
    this.substitution,
    this.sortMinute,
  });

  final String minuteLabel;
  final String text;
  final IconData icon;

  /// Score cumulé après ce but. `null` sur un remplacement.
  final String? scoreLabel;
  final MatchLiveEvent? substitution;

  /// Minute servant au tri. `null` quand elle est inconnue : la ligne garde
  /// alors la place que le compte rendu lui a donnée.
  final int? sortMinute;
  final int order;
}

/// Chronologie des faits d'un match terminé, dans sa fiche.
///
/// Les buts viennent du **compte rendu validé** : c'est la version corrigée par
/// l'administrateur, pas le brouillon saisi en direct. Corriger un buteur ou
/// une minute dans le compte rendu se voit donc immédiatement ici, et un match
/// saisi sans suivi en direct a lui aussi sa chronologie.
///
/// Les remplacements n'existent que dans le journal du direct : ils s'ajoutent
/// à la liste quand ce journal existe.
class MatchFaitsDuMatchCard extends ConsumerWidget {
  const MatchFaitsDuMatchCard({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(matchGoalActionsProvider(matchId)).valueOrNull;
    final timeline = ref.watch(matchLiveTimelineProvider(matchId)).valueOrNull;
    final substitutions = timeline?.events
            .where((event) => event.type == MatchLiveEventType.substitution)
            .toList() ??
        const <MatchLiveEvent>[];

    final rows = _buildRows(goals ?? const [], substitutions);
    if (rows.isEmpty) return const SizedBox.shrink();

    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.timeline_rounded),
        title: const Text('Faits du match'),
        initiallyExpanded: true,
        children: [
          for (final row in rows) _FactLine(row: row),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  List<_FactRow> _buildRows(
    List<MatchGoalAction> goals,
    List<MatchLiveEvent> substitutions,
  ) {
    var scoreAsGrinta = 0;
    var scoreAdverse = 0;
    var order = 0;
    final rows = <_FactRow>[];

    // Les buts arrivent déjà dans l'ordre retenu par le compte rendu : le
    // score cumulé se reconstitue simplement en les parcourant.
    for (final goal in goals) {
      if (goal.isAsGrinta) {
        scoreAsGrinta += 1;
      } else {
        scoreAdverse += 1;
      }
      rows.add(
        _FactRow(
          minuteLabel: goal.minute == null ? '—' : "${goal.minute}'",
          sortMinute: goal.minute,
          order: order++,
          icon: Icons.sports_soccer_rounded,
          scoreLabel: '$scoreAsGrinta-$scoreAdverse',
          text: _goalText(goal),
        ),
      );
    }

    for (final event in substitutions) {
      rows.add(
        _FactRow(
          minuteLabel: "${event.minute}'",
          sortMinute: event.minute,
          order: order++,
          icon: Icons.swap_horiz_rounded,
          text: '',
          substitution: event,
        ),
      );
    }

    // Buts et remplacements se mêlent par minute. Une minute inconnue reste à
    // sa place plutôt que de remonter en tête de match.
    rows.sort((a, b) {
      final minuteA = a.sortMinute;
      final minuteB = b.sortMinute;
      if (minuteA != null && minuteB != null && minuteA != minuteB) {
        return minuteA.compareTo(minuteB);
      }
      return a.order.compareTo(b.order);
    });
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
    final substitution = row.substitution;
    return ListTile(
      dense: true,
      leading: Icon(row.icon, size: 20),
      title: substitution == null
          ? Text(row.text)
          : LiveSubstitutionLine(
              playerInName: substitution.playerInName ?? '?',
              playerOutName: substitution.playerOutName ?? '?',
            ),
      subtitle: row.scoreLabel == null ? null : Text(row.scoreLabel!),
      trailing: Text(
        row.minuteLabel,
        style: const TextStyle(fontWeight: FontWeight.w400),
      ),
    );
  }
}
