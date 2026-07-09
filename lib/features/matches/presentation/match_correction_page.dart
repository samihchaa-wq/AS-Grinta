import 'package:as_grinta/features/matches/data/match_correction_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MatchCorrectionPage extends ConsumerWidget {
  const MatchCorrectionPage({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(matchCorrectionProvider(matchId));

    return Scaffold(
      appBar: AppBar(title: const Text('Correction post-match')),
      floatingActionButton: dataAsync.valueOrNull == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _editGoal(
                context,
                ref,
                dataAsync.valueOrNull!,
                null,
              ),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un but'),
            ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(matchCorrectionProvider(matchId));
          await ref.read(matchCorrectionProvider(matchId).future);
        },
        child: dataAsync.when(
          loading: () => const ListView(
            children: [
              SizedBox(height: 220),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [Text(error.toString())],
          ),
          data: (data) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Score recalculé : ${data.scoreGrinta} - ${data.scoreOpponent}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text('Statut : ${data.status}'),
                      const SizedBox(height: 8),
                      const Text(
                        'Toute correction est journalisée. Le score est toujours '
                        'recalculé depuis les événements, jamais saisi séparément.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: data.motmProfileId,
                decoration: const InputDecoration(
                  labelText: 'Homme du match corrigé',
                ),
                items: data.participants
                    .map(
                      (participant) => DropdownMenuItem<String>(
                        value: participant.id,
                        child: Text(participant.name),
                      ),
                    )
                    .toList(),
                onChanged: (profileId) async {
                  if (profileId == null) return;
                  await ref.read(matchCorrectionRepositoryProvider).setMotm(
                        matchId: matchId,
                        profileId: profileId,
                      );
                  ref.invalidate(matchCorrectionProvider(matchId));
                },
              ),
              const SizedBox(height: 20),
              Text('Buts', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              if (data.goals.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Aucun but enregistré.'),
                  ),
                )
              else
                ...data.goals.map(
                  (goal) => Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text('${goal.minute}’')),
                      title: Text(
                        goal.team == 'as_grinta'
                            ? 'But AS Grinta'
                            : 'But adverse',
                      ),
                      subtitle: Text(
                        _goalDescription(goal, data.participants),
                      ),
                      onTap: () => _editGoal(context, ref, data, goal),
                      trailing: IconButton(
                        tooltip: 'Supprimer',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteGoal(context, ref, goal),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _goalDescription(
    CorrectionGoal goal,
    List<CorrectionParticipant> participants,
  ) {
    String name(String? id) {
      if (id == null) return 'aucun';
      for (final participant in participants) {
        if (participant.id == id) return participant.name;
      }
      return 'joueur archivé';
    }

    if (goal.team == 'adverse') return 'Adversaire';
    if (goal.goalType == 'csc_adverse') return 'CSC adverse';
    return '${goal.goalType ?? 'jeu'} • ${name(goal.scorerId)} • '
        'passeur : ${name(goal.assisterId)}';
  }

  Future<void> _editGoal(
    BuildContext context,
    WidgetRef ref,
    MatchCorrectionData data,
    CorrectionGoal? existing,
  ) async {
    var team = existing?.team ?? 'as_grinta';
    var minute = existing?.minute ?? 0;
    var goalType = existing?.goalType ?? 'jeu';
    String? scorerId = existing?.scorerId;
    String? assisterId = existing?.assisterId;
    final minuteController = TextEditingController(text: '$minute');

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final hidesPlayers = team == 'adverse' || goalType == 'csc_adverse';
          return AlertDialog(
            title: Text(existing == null ? 'Ajouter un but' : 'Corriger le but'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: team,
                    decoration: const InputDecoration(labelText: 'Équipe'),
                    items: const [
                      DropdownMenuItem(
                        value: 'as_grinta',
                        child: Text('AS Grinta'),
                      ),
                      DropdownMenuItem(
                        value: 'adverse',
                        child: Text('Adversaire'),
                      ),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        team = value ?? 'as_grinta';
                        if (team == 'adverse') {
                          scorerId = null;
                          assisterId = null;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: minuteController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Minute'),
                  ),
                  if (team == 'as_grinta') ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: goalType,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: const [
                        DropdownMenuItem(value: 'jeu', child: Text('Jeu')),
                        DropdownMenuItem(
                          value: 'penalty',
                          child: Text('Penalty'),
                        ),
                        DropdownMenuItem(
                          value: 'coup_franc',
                          child: Text('Coup franc'),
                        ),
                        DropdownMenuItem(
                          value: 'csc_adverse',
                          child: Text('CSC adverse'),
                        ),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          goalType = value ?? 'jeu';
                          if (goalType == 'csc_adverse') {
                            scorerId = null;
                            assisterId = null;
                          }
                        });
                      },
                    ),
                  ],
                  if (!hidesPlayers) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: scorerId,
                      decoration: const InputDecoration(labelText: 'Buteur'),
                      items: data.participants
                          .map(
                            (participant) => DropdownMenuItem<String>(
                              value: participant.id,
                              child: Text(participant.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => scorerId = value),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      value: assisterId,
                      decoration: const InputDecoration(labelText: 'Passeur'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Sans passe'),
                        ),
                        ...data.participants
                            .where((participant) => participant.id != scorerId)
                            .map(
                              (participant) => DropdownMenuItem<String?>(
                                value: participant.id,
                                child: Text(participant.name),
                              ),
                            ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => assisterId = value),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () {
                  minute = int.tryParse(minuteController.text) ?? -1;
                  if (minute < 0 || minute > 100) return;
                  if (!hidesPlayers && scorerId == null) return;
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Enregistrer'),
              ),
            ],
          );
        },
      ),
    );
    minuteController.dispose();
    if (accepted != true || !context.mounted) return;

    final hidesPlayers = team == 'adverse' || goalType == 'csc_adverse';
    final repository = ref.read(matchCorrectionRepositoryProvider);
    if (existing == null) {
      await repository.addGoal(
        matchId: matchId,
        team: team,
        minute: minute,
        goalType: team == 'adverse' ? null : goalType,
        scorerId: hidesPlayers ? null : scorerId,
        assistType:
            hidesPlayers ? null : (assisterId == null ? 'sans_passe' : 'connu'),
        assisterId: hidesPlayers ? null : assisterId,
      );
    } else {
      await repository.updateGoal(
        goalId: existing.id,
        team: team,
        minute: minute,
        goalType: team == 'adverse' ? null : goalType,
        scorerId: hidesPlayers ? null : scorerId,
        assistType:
            hidesPlayers ? null : (assisterId == null ? 'sans_passe' : 'connu'),
        assisterId: hidesPlayers ? null : assisterId,
      );
    }
    ref.invalidate(matchCorrectionProvider(matchId));
  }

  Future<void> _deleteGoal(
    BuildContext context,
    WidgetRef ref,
    CorrectionGoal goal,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer ce but ?'),
        content: const Text(
          'Le score sera recalculé automatiquement et la suppression sera auditée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(matchCorrectionRepositoryProvider).deleteGoal(goal.id);
    ref.invalidate(matchCorrectionProvider(matchId));
  }
}
