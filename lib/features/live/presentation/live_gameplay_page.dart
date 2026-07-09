import 'package:as_grinta/features/live/domain/live_gameplay.dart';
import 'package:as_grinta/features/live/presentation/live_gameplay_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LiveGameplayPage extends ConsumerStatefulWidget {
  const LiveGameplayPage({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<LiveGameplayPage> createState() => _LiveGameplayPageState();
}

class _LiveGameplayPageState extends ConsumerState<LiveGameplayPage> {
  final List<LivePlayer> _players = const [
    LivePlayer(id: 'p1', name: 'Alice'),
    LivePlayer(id: 'p2', name: 'Bob'),
    LivePlayer(id: 'p3', name: 'Charlie'),
    LivePlayer(id: 'p4', name: 'Diana'),
    LivePlayer(id: 'p5', name: 'Eve'),
    LivePlayer(id: 'p6', name: 'Frank'),
    LivePlayer(id: 'p7', name: 'Grace'),
    LivePlayer(id: 'p8', name: 'Hugo'),
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(liveGameplayControllerProvider(widget.matchId).notifier).initialize(players: _players));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(liveGameplayControllerProvider(widget.matchId));
    final gameplay = state.gameplay;
    if (gameplay == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final formationOptions = LiveGameplayState.supportedFormations;

    return Scaffold(
      appBar: AppBar(title: Text('Live Match • ${widget.matchId}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Composition', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: gameplay.formationKey,
            decoration: const InputDecoration(labelText: 'Formation'),
            items: formationOptions
                .map((formation) => DropdownMenuItem(value: formation, child: Text(formation)))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                ref.read(liveGameplayControllerProvider(widget.matchId).notifier).changeFormation(value);
              }
            },
          ),
          const SizedBox(height: 16),
          _PitchView(gameplay: gameplay, matchId: widget.matchId),
          const SizedBox(height: 16),
          Text('Banc de touche', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: gameplay.bench.map((playerId) {
              final player = _players.firstWhere((item) => item.id == playerId, orElse: () => const LivePlayer(id: '', name: ''));
              return Draggable<String>(
                data: playerId,
                feedback: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  child: Chip(label: Text(player.name)),
                ),
                child: Chip(label: Text(player.name)),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _showGoalDialog(context, ref),
                  icon: const Icon(Icons.sports_soccer),
                  label: const Text('Ajouter un but'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showSubstitutionDialog(context, ref),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Remplacement'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Buts', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...gameplay.goals.map((goal) => ListTile(
                title: Text('${goal.team} • ${goal.minute}’ • ${goal.type.name}'),
                subtitle: Text('Buteur: ${goal.scorerId ?? '-'} • Passeur: ${goal.assisterId ?? '-'}'),
                trailing: Wrap(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _showGoalDialog(context, ref, existingGoal: goal),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => ref.read(liveGameplayControllerProvider(widget.matchId).notifier).removeGoal(goal.id),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 16),
          Text('Historique des remplacements', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...gameplay.substitutions.map((sub) => ListTile(
                title: Text('${sub.minute}’ • ${_playerName(_players, sub.inPlayerId)} entre en jeu'),
                subtitle: Text('Sortie : ${_playerName(_players, sub.outPlayerId)}'),
              )),
        ],
      ),
    );
  }

  void _showGoalDialog(BuildContext context, WidgetRef ref, {LiveGoal? existingGoal}) {
    final teamController = TextEditingController(text: existingGoal?.team ?? 'grinta');
    final minuteController = TextEditingController(text: existingGoal?.minute.toString() ?? '0');
    final typeController = ValueNotifier<GoalType>(existingGoal?.type ?? GoalType.openPlay);
    final scorerController = ValueNotifier<String?>(existingGoal?.scorerId);
    final assisterController = ValueNotifier<String?>(existingGoal?.assisterId);

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(existingGoal == null ? 'Ajouter un but' : 'Modifier le but'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: teamController.text,
                items: const [
                  DropdownMenuItem(value: 'grinta', child: Text('AS Grinta')),
                  DropdownMenuItem(value: 'adversaire', child: Text('Adversaire')),
                ],
                onChanged: (value) => teamController.text = value ?? 'grinta',
                decoration: const InputDecoration(labelText: 'Équipe'),
              ),
              TextField(
                controller: minuteController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Minute'),
              ),
              DropdownButtonFormField<GoalType>(
                value: typeController.value,
                items: GoalType.values.map((type) => DropdownMenuItem(value: type, child: Text(_goalTypeLabel(type)))).toList(),
                onChanged: (value) {
                  if (value != null) {
                    typeController.value = value;
                    if (value == GoalType.ownGoal) {
                      scorerController.value = null;
                      assisterController.value = null;
                    }
                  }
                },
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              ValueListenableBuilder<GoalType>(
                valueListenable: typeController,
                builder: (_, type, __) {
                  if (type == GoalType.ownGoal) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    children: [
                      DropdownButtonFormField<String>(
                        value: scorerController.value,
                        items: _players.map((player) => DropdownMenuItem(value: player.id, child: Text(player.name))).toList(),
                        onChanged: (value) => scorerController.value = value,
                        decoration: const InputDecoration(labelText: 'Buteur'),
                      ),
                      DropdownButtonFormField<String>(
                        value: assisterController.value,
                        items: _players.map((player) => DropdownMenuItem(value: player.id, child: Text(player.name))).toList(),
                        onChanged: (value) => assisterController.value = value,
                        decoration: const InputDecoration(labelText: 'Passeur'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final notifier = ref.read(liveGameplayControllerProvider(widget.matchId).notifier);
                final minute = int.tryParse(minuteController.text) ?? 0;
                if (existingGoal == null) {
                  notifier.addGoal(
                    team: teamController.text,
                    minute: minute,
                    type: typeController.value,
                    scorerId: scorerController.value,
                    assisterId: assisterController.value,
                  );
                } else {
                  notifier.updateGoal(
                    goalId: existingGoal.id,
                    team: teamController.text,
                    minute: minute,
                    type: typeController.value,
                    scorerId: scorerController.value,
                    assisterId: assisterController.value,
                  );
                }
                Navigator.of(dialogContext).pop();
              },
              child: Text(existingGoal == null ? 'Ajouter' : 'Enregistrer'),
            ),
          ],
        );
      },
    );
  }

  void _showSubstitutionDialog(BuildContext context, WidgetRef ref) {
    final minuteController = TextEditingController(text: '0');
    final inPlayerController = ValueNotifier<String?>(_players.first.id);
    final outPlayerController = ValueNotifier<String?>(_players.first.id);

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Ajouter un remplacement'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: minuteController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Minute'),
              ),
              DropdownButtonFormField<String>(
                value: inPlayerController.value,
                items: _players.map((player) => DropdownMenuItem(value: player.id, child: Text(player.name))).toList(),
                onChanged: (value) => inPlayerController.value = value,
                decoration: const InputDecoration(labelText: 'Entrée'),
              ),
              DropdownButtonFormField<String>(
                value: outPlayerController.value,
                items: _players.map((player) => DropdownMenuItem(value: player.id, child: Text(player.name))).toList(),
                onChanged: (value) => outPlayerController.value = value,
                decoration: const InputDecoration(labelText: 'Sortie'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final notifier = ref.read(liveGameplayControllerProvider(widget.matchId).notifier);
                final minute = int.tryParse(minuteController.text) ?? 0;
                notifier.addSubstitution(
                  minute: minute,
                  inPlayerId: inPlayerController.value ?? '',
                  outPlayerId: outPlayerController.value ?? '',
                );
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
  }

  String _playerName(List<LivePlayer> players, String playerId) {
    return players.firstWhere((player) => player.id == playerId, orElse: () => const LivePlayer(id: '', name: '-')).name;
  }

  String _goalTypeLabel(GoalType type) {
    return switch (type) {
      GoalType.openPlay => 'Jeu',
      GoalType.penalty => 'Penalty',
      GoalType.freeKick => 'Coup franc',
      GoalType.ownGoal => 'CSC adverse',
    };
  }
}

class _PitchView extends StatelessWidget {
  const _PitchView({required this.gameplay, required this.matchId});

  final LiveGameplayState gameplay;
  final String matchId;

  @override
  Widget build(BuildContext context) {
    final slots = LiveGameplayState.formationSlots(gameplay.formationKey);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade700),
        color: Colors.green.shade800,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Consumer(
                  builder: (context, ref, _) => _PitchSlot(
                    label: 'Position',
                    slotKey: slots.first,
                    playerId: gameplay.lineup[slots.first],
                    onAccept: (playerId) => ref.read(liveGameplayControllerProvider(matchId).notifier).movePlayer(playerId: playerId, slotKey: slots.first),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...slots.skip(1).map((slot) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Consumer(
                  builder: (context, ref, _) => _PitchSlot(
                    label: slot,
                    slotKey: slot,
                    playerId: gameplay.lineup[slot],
                    onAccept: (playerId) => ref.read(liveGameplayControllerProvider(matchId).notifier).movePlayer(playerId: playerId, slotKey: slot),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

class _PitchSlot extends StatelessWidget {
  const _PitchSlot({required this.label, required this.slotKey, required this.playerId, required this.onAccept});

  final String label;
  final String slotKey;
  final String? playerId;
  final ValueChanged<String> onAccept;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      builder: (context, candidateData, rejectedData) {
        return Draggable<String>(
          data: playerId ?? '',
          feedback: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.white,
              child: Text(playerId ?? label),
            ),
          ),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(child: Text(playerId ?? label)),
          ),
        );
      },
      onAcceptWithDetails: (details) {
        if (details.data.isNotEmpty) {
          onAccept(details.data);
        }
      },
    );
  }
}
