import 'package:as_grinta/features/matches/domain/match_finalization.dart';
import 'package:as_grinta/features/matches/presentation/match_finalization_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MatchFinalizationPage extends ConsumerWidget {
  const MatchFinalizationPage({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(matchFinalizationControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Finalisation du match')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Validation finale', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(labelText: 'Score Grinta'),
              keyboardType: TextInputType.number,
              onChanged: (value) {},
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(labelText: 'Score adversaire'),
              keyboardType: TextInputType.number,
              onChanged: (value) {},
            ),
            const SizedBox(height: 16),
            if (state.validation != null) ...[
              Text('Résultat : ${state.validation!.isValid ? 'OK' : 'À corriger'}'),
              ...state.validation!.issues.map((issue) => Text('• $issue')),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                ref.read(matchFinalizationControllerProvider.notifier).finalizeMatch(
                  matchId: matchId,
                  grintaScore: 2,
                  opponentScore: 1,
                  goals: const [
                    MatchGoal(team: 'grinta', minute: 10, scorerId: 'p1', assisterId: 'p2'),
                    MatchGoal(team: 'adversaire', minute: 45, scorerId: 'p3', assisterId: null),
                  ],
                  substitutions: const [
                    MatchSubstitution(minute: 60, inPlayerId: 'p4', outPlayerId: 'p5'),
                  ],
                  manOfTheMatchId: null,
                );
              },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Finaliser le match'),
            ),
          ],
        ),
      ),
    );
  }
}
