import 'package:as_grinta/features/match_live/domain/match_live_event.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/live_substitution_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef _ScoredEvent = ({
  MatchLiveEvent event,
  int scoreAsGrinta,
  int scoreAdverse
});

/// Chronologie des buts et remplacements d'un match suivi en direct, dans
/// la fiche du match fini. `null` (match jamais suivi via le Tableau Blanc)
/// n'affiche rien.
class MatchFaitsDuMatchCard extends ConsumerWidget {
  const MatchFaitsDuMatchCard({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timelineAsync = ref.watch(matchLiveTimelineProvider(matchId));
    final timeline = timelineAsync.valueOrNull;
    if (timeline == null || timeline.events.isEmpty) {
      return const SizedBox.shrink();
    }

    // Chaque événement de but ne porte que le nouveau score de son propre
    // camp ; on reconstitue le score cumulé en parcourant la chronologie
    // complète (toutes mi-temps confondues) dans l'ordre.
    var scoreAsGrinta = 0;
    var scoreAdverse = 0;
    final scored = <_ScoredEvent>[];
    for (final event in timeline.events) {
      if (event.type == MatchLiveEventType.goalUs) {
        scoreAsGrinta = event.scoreAsGrintaAfter ?? scoreAsGrinta;
      } else if (event.type == MatchLiveEventType.goalThem) {
        scoreAdverse = event.scoreAdverseAfter ?? scoreAdverse;
      }
      scored.add((
        event: event,
        scoreAsGrinta: scoreAsGrinta,
        scoreAdverse: scoreAdverse,
      ));
    }

    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.timeline_rounded),
        title: const Text('Faits du match'),
        initiallyExpanded: true,
        children: [
          _HalfSection(
            label: '1ʳᵉ mi-temps',
            events: scored.where((row) => row.event.half == 1).toList(),
          ),
          if (scored.any((row) => row.event.half == 2))
            _HalfSection(
              label: '2ᵉ mi-temps',
              events: scored.where((row) => row.event.half == 2).toList(),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _HalfSection extends StatelessWidget {
  const _HalfSection({required this.label, required this.events});

  final String label;
  final List<_ScoredEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: .6,
                ),
          ),
        ),
        for (final row in events) _EventLine(row: row),
      ],
    );
  }
}

class _EventLine extends StatelessWidget {
  const _EventLine({required this.row});

  final _ScoredEvent row;

  @override
  Widget build(BuildContext context) {
    final event = row.event;
    final (icon, text) = switch (event.type) {
      MatchLiveEventType.goalUs => (
          Icons.sports_soccer_rounded,
          event.isOpponentOwnGoal
              ? 'CSC adverse'
              : (event.scorerName ?? 'But AS Grinta'),
        ),
      MatchLiveEventType.goalThem => (
          Icons.sports_soccer_rounded,
          'But adverse',
        ),
      // Le libellé n'est pas utilisé : un remplacement s'affiche avec des
      // flèches (LiveSubstitutionLine), pas en toutes lettres.
      MatchLiveEventType.substitution => (Icons.swap_horiz_rounded, ''),
    };
    final isGoal = event.type != MatchLiveEventType.substitution;
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20),
      title: isGoal
          ? Text(text)
          : LiveSubstitutionLine(
              playerInName: event.playerInName ?? '?',
              playerOutName: event.playerOutName ?? '?',
            ),
      subtitle:
          isGoal ? Text('${row.scoreAsGrinta}-${row.scoreAdverse}') : null,
      trailing: Text(
        "${event.minute}'",
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}
