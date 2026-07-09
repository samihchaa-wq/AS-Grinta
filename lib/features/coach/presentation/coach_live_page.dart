import 'package:as_grinta/features/coach/domain/coach_board.dart';
import 'package:as_grinta/features/coach/presentation/coach_board_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CoachLivePage extends ConsumerWidget {
  const CoachLivePage({super.key});

  String _timer(int seconds) {
    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remaining.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(coachBoardControllerProvider);
    final controller = ref.read(coachBoardControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tableau du match'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                _timer(state.elapsedSeconds),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(coachBoardControllerProvider),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!state.canEdit)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.visibility_outlined),
                        title: Text('Lecture seule'),
                        subtitle: Text(
                          'La composition, le score, le chrono et les événements sont synchronisés en direct.',
                        ),
                      ),
                    ),
                  if (state.error != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          state.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  _ScoreAndTimerCard(
                    state: state,
                    controller: controller,
                  ),
                  const SizedBox(height: 16),
                  _LineupCard(
                    state: state,
                    controller: controller,
                  ),
                  const SizedBox(height: 16),
                  _EventsCard(
                    state: state,
                    controller: controller,
                  ),
                ],
              ),
            ),
    );
  }
}

class _ScoreAndTimerCard extends StatelessWidget {
  const _ScoreAndTimerCard({
    required this.state,
    required this.controller,
  });

  final CoachBoardState state;
  final CoachBoardController controller;

  Future<void> _confirmEnd(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Terminer le match ?'),
        content: Text(
          'Score actuel : AS Grinta ${state.scoreUs} - ${state.scoreThem} Adversaire',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Terminer'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.endMatch();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text('AS Grinta'),
                      Text(
                        '${state.scoreUs}',
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                    ],
                  ),
                ),
                const Text('-', style: TextStyle(fontSize: 30)),
                Expanded(
                  child: Column(
                    children: [
                      const Text('Adversaire'),
                      Text(
                        '${state.scoreThem}',
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (state.canEdit)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: state.lineup.length != 11
                        ? null
                        : state.isRunning
                            ? controller.pauseTimer
                            : controller.startTimer,
                    icon: Icon(
                      state.isRunning ? Icons.pause : Icons.play_arrow,
                    ),
                    label: Text(state.isRunning ? 'Pause' : 'Démarrer'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.goToHalfTime,
                    icon: const Icon(Icons.timelapse),
                    label: const Text('Mi-temps'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _confirmEnd(context),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Fin du match'),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.isRunning ? null : controller.resetBoard,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Réinitialiser'),
                  ),
                ],
              ),
            if (state.canEdit && state.lineup.length != 11) ...[
              const SizedBox(height: 10),
              const Text('Place 11 titulaires pour pouvoir démarrer le match.'),
            ],
          ],
        ),
      ),
    );
  }
}

class _LineupCard extends StatelessWidget {
  const _LineupCard({required this.state, required this.controller});

  final CoachBoardState state;
  final CoachBoardController controller;

  String _slotLabel(String slot) {
    return switch (slot) {
      'gk' => 'G',
      'lb' => 'DG',
      'cb1' || 'cb2' => 'DC',
      'rb' => 'DD',
      'dm' => 'MDC',
      'cm1' || 'cm2' => 'MC',
      'lw' => 'AG',
      'st' => 'BU',
      'rw' => 'AD',
      _ => slot.toUpperCase(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final used = state.lineup.values.toSet();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Composition 4-3-3',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text('${state.lineup.length}/11'),
              ],
            ),
            const SizedBox(height: 12),
            ...state.formationSlots.map((slot) {
              final selectedId = state.lineup[slot];
              final available = state.players
                  .where((player) =>
                      player.id == selectedId || !used.contains(player.id))
                  .toList();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DropdownButtonFormField<String>(
                  initialValue: selectedId,
                  decoration: InputDecoration(
                    labelText: _slotLabel(slot),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  items: available
                      .map(
                        (player) => DropdownMenuItem(
                          value: player.id,
                          child: Text(player.displayName),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: state.canEdit
                      ? (playerId) {
                          if (playerId != null) {
                            controller.movePlayer(playerId, slot);
                          }
                        }
                      : null,
                ),
              );
            }),
            const Divider(height: 24),
            Text('Banc', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: state.bench.map((id) {
                final player = state.playerById(id);
                return Chip(label: Text(player?.displayName ?? 'Joueur'));
              }).toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventsCard extends StatelessWidget {
  const _EventsCard({required this.state, required this.controller});

  final CoachBoardState state;
  final CoachBoardController controller;

  Future<void> _addGoal(BuildContext context) async {
    String? scorerId;
    String? assistId;
    final lineupPlayers = state.lineup.values
        .map(state.playerById)
        .whereType<CoachPlayer>()
        .toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('But AS Grinta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: scorerId,
                decoration: const InputDecoration(labelText: 'Buteur'),
                items: lineupPlayers
                    .map(
                      (player) => DropdownMenuItem(
                        value: player.id,
                        child: Text(player.displayName),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setDialogState(() => scorerId = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: assistId,
                decoration: const InputDecoration(
                  labelText: 'Passeur (facultatif)',
                ),
                items: lineupPlayers
                    .where((player) => player.id != scorerId)
                    .map(
                      (player) => DropdownMenuItem(
                        value: player.id,
                        child: Text(player.displayName),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setDialogState(() => assistId = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: scorerId == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await controller.addGoalUs(scorerId: scorerId, assistId: assistId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goalCounts = <String, int>{};
    final assistCounts = <String, int>{};
    for (final event in state.events) {
      if (event.type == CoachEventType.goalUs && event.playerId != null) {
        goalCounts.update(event.playerId!, (value) => value + 1, ifAbsent: () => 1);
      }
      if (event.assistPlayerId != null) {
        assistCounts.update(
          event.assistPlayerId!,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Événements',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (state.canEdit) ...[
                  IconButton.filledTonal(
                    tooltip: 'But AS Grinta',
                    onPressed: () => _addGoal(context),
                    icon: const Icon(Icons.sports_soccer),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'But adversaire',
                    onPressed: controller.addGoalThem,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            if (state.events.isEmpty)
              const Text('Aucun événement enregistré.')
            else
              ...state.events.reversed.map((event) {
                final scorer = state.playerById(event.playerId);
                final assister = state.playerById(event.assistPlayerId);
                final playerIn = state.playerById(event.playerInId);
                final playerOut = state.playerById(event.playerOutId);
                final title = switch (event.type) {
                  CoachEventType.goalUs =>
                    '⚽ ${scorer?.displayName ?? 'Buteur non renseigné'}${assister == null ? '' : ' · 👟 ${assister.displayName}'}',
                  CoachEventType.goalThem => 'But adversaire',
                  CoachEventType.substitution =>
                    '${playerOut?.displayName ?? 'Joueur'} → ${playerIn?.displayName ?? 'Joueur'}',
                  _ => event.type.label,
                };
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Text("${event.minute}'")),
                  title: Text(title),
                  trailing: state.canEdit
                      ? IconButton(
                          tooltip: 'Supprimer',
                          onPressed: () => controller.removeEvent(event.id),
                          icon: const Icon(Icons.delete_outline),
                        )
                      : null,
                );
              }),
            if (goalCounts.isNotEmpty || assistCounts.isNotEmpty) ...[
              const Divider(height: 24),
              ...state.players.where((player) {
                return goalCounts.containsKey(player.id) ||
                    assistCounts.containsKey(player.id);
              }).map((player) {
                final goals = goalCounts[player.id] ?? 0;
                final assists = assistCounts[player.id] ?? 0;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(player.displayName),
                  trailing: Text(
                    '${List.filled(goals, '⚽').join()}${List.filled(assists, '👟').join()}',
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
