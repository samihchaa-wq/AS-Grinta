import 'package:as_grinta/features/live/data/live_setup_repository.dart';
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
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final setupAsync = ref.watch(liveSetupProvider(widget.matchId));

    return setupAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Live Match')),
        body: _ErrorState(
          message: error.toString(),
          onRetry: () => ref.invalidate(liveSetupProvider(widget.matchId)),
        ),
      ),
      data: (setup) {
        if (setup.players.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Live Match')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aucun participant actif n’est associé à ce match. '
                  'La composition ne peut pas être ouverte.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        if (setup.formations.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Live Match')),
            body: const Center(
              child: Text('Aucune formation Supabase disponible.'),
            ),
          );
        }

        if (!_initialized) {
          _initialized = true;
          Future.microtask(() {
            if (!mounted) return;
            ref
                .read(liveGameplayControllerProvider(widget.matchId).notifier)
                .initialize(
                  players: setup.players,
                  formationKey: setup.formations.first.code,
                );
          });
        }

        return _GameplayBody(
          matchId: widget.matchId,
          formations: setup.formations,
        );
      },
    );
  }
}

class _GameplayBody extends ConsumerWidget {
  const _GameplayBody({
    required this.matchId,
    required this.formations,
  });

  final String matchId;
  final List<LiveFormationDefinition> formations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(liveGameplayControllerProvider(matchId));
    final gameplay = state.gameplay;

    if (state.isLoading || gameplay == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (state.error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live Match')),
        body: _ErrorState(
          message: state.error!,
          onRetry: () => ref
              .read(liveGameplayControllerProvider(matchId).notifier)
              .reload(),
        ),
      );
    }

    final selectedFormation = formations.firstWhere(
      (formation) => formation.code == gameplay.formationKey,
      orElse: () => formations.first,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Composition & déroulé')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: selectedFormation.code,
            decoration: const InputDecoration(labelText: 'Formation'),
            items: formations
                .map(
                  (formation) => DropdownMenuItem(
                    value: formation.code,
                    child: Text(formation.label),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                ref
                    .read(liveGameplayControllerProvider(matchId).notifier)
                    .changeFormation(value);
              }
            },
          ),
          const SizedBox(height: 16),
          _PitchView(
            gameplay: gameplay,
            matchId: matchId,
            slots: selectedFormation.slots,
          ),
          const SizedBox(height: 16),
          Text('Banc de touche',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: gameplay.bench.map((playerId) {
              final player = _playerById(gameplay.players, playerId);
              return Draggable<String>(
                data: playerId,
                feedback: Material(
                  elevation: 4,
                  child: Chip(label: Text(player?.name ?? 'Joueur')),
                ),
                child: Chip(label: Text(player?.name ?? 'Joueur')),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _showGoalDialog(context, ref, gameplay),
                  icon: const Icon(Icons.sports_soccer),
                  label: const Text('Ajouter un but'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: gameplay.bench.isEmpty || gameplay.lineup.isEmpty
                      ? null
                      : () => _showSubstitutionDialog(context, ref, gameplay),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Remplacement'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Buts', style: Theme.of(context).textTheme.titleLarge),
          ...gameplay.goals.map(
            (goal) => ListTile(
              title: Text('${goal.team} • ${goal.minute}’'),
              subtitle: Text(
                'Buteur : ${_playerById(gameplay.players, goal.scorerId)?.name ?? '-'} '
                '• Passeur : ${_playerById(gameplay.players, goal.assisterId)?.name ?? '-'}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => ref
                    .read(liveGameplayControllerProvider(matchId).notifier)
                    .removeGoal(goal.id),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Historique des remplacements',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          ...gameplay.substitutions.map(
            (substitution) => ListTile(
              title: Text('${substitution.minute}’'),
              subtitle: Text(
                '${_playerById(gameplay.players, substitution.inPlayerId)?.name ?? '-'} entre '
                '• ${_playerById(gameplay.players, substitution.outPlayerId)?.name ?? '-'} sort',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showGoalDialog(
    BuildContext context,
    WidgetRef ref,
    LiveGameplayState gameplay,
  ) {
    var team = 'grinta';
    var type = GoalType.openPlay;
    String? scorerId;
    String? assisterId;
    final minuteController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final hidesPlayers = team == 'adversaire' || type == GoalType.ownGoal;
          return AlertDialog(
            title: const Text('Ajouter un but'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: team,
                    decoration: const InputDecoration(labelText: 'Équipe'),
                    items: const [
                      DropdownMenuItem(
                          value: 'grinta', child: Text('AS Grinta')),
                      DropdownMenuItem(
                          value: 'adversaire', child: Text('Adversaire')),
                    ],
                    onChanged: (value) => setDialogState(() {
                      team = value ?? 'grinta';
                      if (team == 'adversaire') {
                        scorerId = null;
                        assisterId = null;
                      }
                    }),
                  ),
                  TextField(
                    controller: minuteController,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Minute (0-100)'),
                  ),
                  DropdownButtonFormField<GoalType>(
                    value: type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: GoalType.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(() {
                      type = value ?? GoalType.openPlay;
                      if (type == GoalType.ownGoal) {
                        scorerId = null;
                        assisterId = null;
                      }
                    }),
                  ),
                  if (!hidesPlayers) ...[
                    DropdownButtonFormField<String>(
                      value: scorerId,
                      decoration: const InputDecoration(labelText: 'Buteur'),
                      items: gameplay.players
                          .map(
                            (player) => DropdownMenuItem(
                              value: player.id,
                              child: Text(player.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => scorerId = value),
                    ),
                    DropdownButtonFormField<String>(
                      value: assisterId,
                      decoration: const InputDecoration(labelText: 'Passeur'),
                      items: gameplay.players
                          .where((player) => player.id != scorerId)
                          .map(
                            (player) => DropdownMenuItem(
                              value: player.id,
                              child: Text(player.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => assisterId = value),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () {
                  final minute = int.tryParse(minuteController.text);
                  if (minute == null || minute < 0 || minute > 100) return;
                  if (!hidesPlayers && scorerId == null) return;
                  ref
                      .read(liveGameplayControllerProvider(matchId).notifier)
                      .addGoal(
                        team: team,
                        minute: minute,
                        type: type,
                        scorerId: hidesPlayers ? null : scorerId,
                        assisterId: hidesPlayers ? null : assisterId,
                      );
                  Navigator.pop(dialogContext);
                },
                child: const Text('Ajouter'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSubstitutionDialog(
    BuildContext context,
    WidgetRef ref,
    LiveGameplayState gameplay,
  ) {
    String? inPlayerId = gameplay.bench.firstOrNull;
    String? outPlayerId = gameplay.lineup.values.firstOrNull;
    final minuteController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Remplacement'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: minuteController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Minute (0-100)'),
              ),
              DropdownButtonFormField<String>(
                value: inPlayerId,
                decoration: const InputDecoration(labelText: 'Entrée'),
                items: gameplay.bench
                    .map((id) => _playerById(gameplay.players, id))
                    .whereType<LivePlayer>()
                    .map(
                      (player) => DropdownMenuItem(
                        value: player.id,
                        child: Text(player.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => inPlayerId = value),
              ),
              DropdownButtonFormField<String>(
                value: outPlayerId,
                decoration: const InputDecoration(labelText: 'Sortie'),
                items: gameplay.lineup.values
                    .map((id) => _playerById(gameplay.players, id))
                    .whereType<LivePlayer>()
                    .map(
                      (player) => DropdownMenuItem(
                        value: player.id,
                        child: Text(player.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => outPlayerId = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final minute = int.tryParse(minuteController.text);
                if (minute == null || minute < 0 || minute > 100) return;
                if (inPlayerId == null || outPlayerId == null) return;
                if (inPlayerId == outPlayerId) return;
                ref
                    .read(liveGameplayControllerProvider(matchId).notifier)
                    .addSubstitution(
                      minute: minute,
                      inPlayerId: inPlayerId!,
                      outPlayerId: outPlayerId!,
                    );
                Navigator.pop(dialogContext);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PitchView extends StatelessWidget {
  const _PitchView({
    required this.gameplay,
    required this.matchId,
    required this.slots,
  });

  final LiveGameplayState gameplay;
  final String matchId;
  final List<String> slots;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade700),
        color: Colors.green.shade800,
      ),
      child: Column(
        children: slots.map((slot) {
          final playerId = gameplay.lineup[slot];
          final player = _playerById(gameplay.players, playerId);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Consumer(
              builder: (context, ref, _) => DragTarget<String>(
                onAcceptWithDetails: (details) => ref
                    .read(liveGameplayControllerProvider(matchId).notifier)
                    .movePlayer(playerId: details.data, slotKey: slot),
                builder: (context, candidates, rejected) => Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(player?.name ?? slot),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}

LivePlayer? _playerById(List<LivePlayer> players, String? id) {
  if (id == null) return null;
  for (final player in players) {
    if (player.id == id) return player;
  }
  return null;
}
