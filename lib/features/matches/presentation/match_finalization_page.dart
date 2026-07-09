import 'package:as_grinta/features/matches/data/match_finalization_repository.dart';
import 'package:as_grinta/features/matches/presentation/match_finalization_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MatchFinalizationPage extends ConsumerStatefulWidget {
  const MatchFinalizationPage({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<MatchFinalizationPage> createState() =>
      _MatchFinalizationPageState();
}

class _MatchFinalizationPageState extends ConsumerState<MatchFinalizationPage> {
  final _grintaScoreController = TextEditingController();
  final _opponentScoreController = TextEditingController();
  String? _motmProfileId;

  @override
  void dispose() {
    _grintaScoreController.dispose();
    _opponentScoreController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchFinalizationControllerProvider);
    final contextAsync = ref.watch(
      matchFinalizationContextProvider(widget.matchId),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Finalisation du match')),
      body: contextAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              error.toString(),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
        data: (finalizationContext) {
          if (finalizationContext.participants.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Impossible de finaliser : aucun participant réel n’est associé au match.',
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Validation finale',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _grintaScoreController,
                decoration: const InputDecoration(labelText: 'Score Grinta'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _opponentScoreController,
                decoration:
                    const InputDecoration(labelText: 'Score adversaire'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _motmProfileId,
                decoration: const InputDecoration(
                  labelText: 'Homme du match',
                ),
                items: finalizationContext.participants
                    .map(
                      (participant) => DropdownMenuItem<String>(
                        value: participant.id,
                        child: Text(participant.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _motmProfileId = value),
              ),
              const SizedBox(height: 12),
              Text(
                '${finalizationContext.goals.length} but(s) et '
                '${finalizationContext.substitutions.length} remplacement(s) enregistrés.',
              ),
              if (state.validation != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Résultat : ${state.validation!.isValid ? 'OK' : 'À corriger'}',
                ),
                ...state.validation!.issues.map((issue) => Text('• $issue')),
              ],
              if (state.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: state.isLoading
                    ? null
                    : () async {
                        final grintaScore =
                            int.tryParse(_grintaScoreController.text);
                        final opponentScore =
                            int.tryParse(_opponentScoreController.text);
                        if (grintaScore == null ||
                            opponentScore == null ||
                            _motmProfileId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Renseignez les deux scores et l’homme du match.',
                              ),
                            ),
                          );
                          return;
                        }

                        await ref
                            .read(matchFinalizationControllerProvider.notifier)
                            .finalizeMatch(
                              matchId: widget.matchId,
                              grintaScore: grintaScore,
                              opponentScore: opponentScore,
                              goals: finalizationContext.goals,
                              substitutions: finalizationContext.substitutions,
                              manOfTheMatchId: _motmProfileId,
                            );

                        if (!context.mounted) return;
                        final latest =
                            ref.read(matchFinalizationControllerProvider);
                        if (latest.error == null &&
                            latest.validation?.isValid == true) {
                          Navigator.of(context).pop();
                        }
                      },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Finaliser le match'),
              ),
            ],
          );
        },
      ),
    );
  }
}
