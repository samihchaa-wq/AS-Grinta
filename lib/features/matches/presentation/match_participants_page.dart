import 'package:as_grinta/features/matches/data/match_participants_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MatchParticipantsPage extends ConsumerWidget {
  const MatchParticipantsPage({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optionsAsync = ref.watch(matchParticipantOptionsProvider(matchId));

    return Scaffold(
      appBar: AppBar(title: const Text('Participants du match')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(matchParticipantOptionsProvider(matchId));
          await ref.read(matchParticipantOptionsProvider(matchId).future);
        },
        child: optionsAsync.when(
          loading: () => ListView(
            children: [
              SizedBox(height: 220),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(error.toString()),
                ),
              ),
            ],
          ),
          data: (options) {
            if (options.isEmpty) {
              return ListView(
                padding: EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Aucun joueur actif n’est présent dans l’effectif de cette saison.',
                      ),
                    ),
                  ),
                ],
              );
            }

            final selectedCount =
                options.where((option) => option.selected).length;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('$selectedCount participant(s) sélectionné(s)'),
                  ),
                ),
                const SizedBox(height: 12),
                ...options.map(
                  (option) => Card(
                    child: CheckboxListTile(
                      value: option.selected,
                      secondary: Icon(
                        option.isGoalkeeper
                            ? Icons.sports_handball
                            : Icons.sports_soccer,
                      ),
                      title: Text(option.name),
                      subtitle: Text(
                        option.isGoalkeeper ? 'Gardien' : 'Joueur de champ',
                      ),
                      onChanged: (value) async {
                        await ref
                            .read(matchParticipantsRepositoryProvider)
                            .setSelected(
                              matchId: matchId,
                              profileId: option.profileId,
                              selected: value == true,
                            );
                        ref.invalidate(
                            matchParticipantOptionsProvider(matchId));
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
