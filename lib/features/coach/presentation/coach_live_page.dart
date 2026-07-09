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
                  _ScoreAndTimerCard(state: state, controller: controller),
                  const SizedBox(height: 16),
                  _LineupCard(state: state, controller: controller),
                  const SizedBox(height: 16),
                  _EventsCard(state: state, controller: controller),
                  const SizedBox(height: 16),
                  _MinutesCard(state: state),
                ],
              ),
            ),
    );
  }
}

class _ScoreAndTimerCard extends StatelessWidget {
  const _ScoreAndTimerCard({required this.state, required this.controller});

  final CoachBoardState state;
  final CoachBoardController controller;

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String action,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
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
                    icon: Icon(state.isRunning ? Icons.pause : Icons.play_arrow),
                    label: Text(state.isRunning ? 'Pause' : 'Démarrer'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await _confirm(
                        context,
                        title: 'Passer à la mi-temps ?',
                        message:
                            'Le chrono sera arrêté et placé à la moitié du temps prévu.',
                        action: 'Mi-temps',
                      );
                      if (ok) await controller.goToHalfTime();
                    },
                    icon: const Icon(Icons.timelapse),
                    label: const Text('Mi-temps'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await _confirm(
                        context,
                        title: 'Terminer le match ?',
                        message:
                            'Score actuel : AS Grinta ${state.scoreUs} - ${state.scoreThem} Adversaire',
                        action: 'Terminer',
                      );
                      if (ok) await controller.endMatch();
                    },
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Fin du match'),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.isRunning
                        ? null
                        : () async {
                            final ok = await _confirm(
                              context,
                              title: 'Réinitialiser le Tableau ?',
                              message:
                                  'La composition, le chrono, le score et tous les événements seront effacés.',
                              action: 'Réinitialiser',
                            );
                            if (ok) await controller.resetBoard();
                          },
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

  String _slotLabel(String slot) => switch (slot) {
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

  String _playerLabel(CoachPlayer player) {
    final goals = state.events
        .where((e) => e.type == CoachEventType.goalUs && e.playerId == player.id)
        .length;
    final assists =
        state.events.where((e) => e.assistPlayerId == player.id).length;
    final icons = '${List.filled(goals, '⚽').join()}'
        '${List.filled(assists, '👟').join()}';
    return icons.isEmpty ? player.displayName : '${player.displayName}  $icons';
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
                    'Composition ${state.formationCode}',
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
                          child: Text(_playerLabel(player)),
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
                return Chip(label: Text(player == null ? 'Joueur' : _playerLabel(player)));
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
                    .map((p) => DropdownMenuItem(value: p.id, child: Text(p.displayName)))
                    .toList(growable: false),
                onChanged: (value) => setDialogState(() {
                  scorerId = value;
                  if (assistId == scorerId) assistId = null;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: assistId,
                decoration:
                    const InputDecoration(labelText: 'Passeur (facultatif)'),
                items: lineupPlayers
                    .where((p) => p.id != scorerId)
                    .map((p) => DropdownMenuItem(value: p.id, child: Text(p.displayName)))
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

  Future<void> _addSubstitution(BuildContext context) async {
    String? outId;
    String? inId;
    final onField = state.lineup.values
        .map(state.playerById)
        .whereType<CoachPlayer>()
        .toList();
    final bench = state.bench
        .map(state.playerById)
        .whereType<CoachPlayer>()
        .toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Remplacement'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: outId,
                decoration: const InputDecoration(labelText: 'Joueur sortant'),
                items: onField
                    .map((p) => DropdownMenuItem(value: p.id, child: Text(p.displayName)))
                    .toList(growable: false),
                onChanged: (value) => setDialogState(() => outId = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: inId,
                decoration: const InputDecoration(labelText: 'Joueur entrant'),
                items: bench
                    .map((p) => DropdownMenuItem(value: p.id, child: Text(p.displayName)))
                    .toList(growable: false),
                onChanged: (value) => setDialogState(() => inId = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: outId == null || inId == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Valider'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && outId != null && inId != null) {
      await controller.addSubstitution(
        inPlayerId: inId!,
        outPlayerId: outId!,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Événements',
                      style: Theme.of(context).textTheme.titleLarge),
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
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Remplacement',
                    onPressed: state.lineup.isEmpty || state.bench.isEmpty
                        ? null
                        : () => _addSubstitution(context),
                    icon: const Icon(Icons.swap_horiz),
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
                    '🔁 ${playerOut?.displayName ?? 'Joueur'} → ${playerIn?.displayName ?? 'Joueur'}',
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
          ],
        ),
      ),
    );
  }
}

class _MinutesCard extends StatelessWidget {
  const _MinutesCard({required this.state});

  final CoachBoardState state;

  Map<String, int> _minutesByPlayer() {
    final currentMinute =
        (state.elapsedSeconds ~/ 60).clamp(0, state.plannedDurationMinutes);
    final substitutions = state.events
        .where((e) => e.type == CoachEventType.substitution)
        .toList()
      ..sort((a, b) => a.minute.compareTo(b.minute));

    final initialField = state.lineup.values.toSet();
    for (final event in substitutions.reversed) {
      if (event.playerInId != null) initialField.remove(event.playerInId);
      if (event.playerOutId != null) initialField.add(event.playerOutId!);
    }

    final enteredAt = <String, int>{for (final id in initialField) id: 0};
    final totals = <String, int>{};

    for (final event in substitutions) {
      final minute = event.minute.clamp(0, currentMinute);
      final outId = event.playerOutId;
      final inId = event.playerInId;
      if (outId != null) {
        final start = enteredAt.remove(outId) ?? 0;
        totals.update(outId, (value) => value + minute - start,
            ifAbsent: () => minute - start);
      }
      if (inId != null) enteredAt[inId] = minute;
    }

    for (final entry in enteredAt.entries) {
      totals.update(entry.key, (value) => value + currentMinute - entry.value,
          ifAbsent: () => currentMinute - entry.value);
    }
    return totals;
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _minutesByPlayer();
    final involvedIds = <String>{
      ...state.lineup.values,
      ...state.events.expand((e) => [e.playerInId, e.playerOutId]).whereType<String>(),
    };
    final players = state.players.where((p) => involvedIds.contains(p.id)).toList()
      ..sort((a, b) => (minutes[b.id] ?? 0).compareTo(minutes[a.id] ?? 0));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Temps de jeu', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (players.isEmpty)
              const Text('Le temps de jeu apparaîtra après la composition.')
            else
              ...players.map((player) {
                final goals = state.events
                    .where((e) =>
                        e.type == CoachEventType.goalUs && e.playerId == player.id)
                    .length;
                final assists = state.events
                    .where((e) => e.assistPlayerId == player.id)
                    .length;
                final icons = '${List.filled(goals, '⚽').join()}'
                    '${List.filled(assists, '👟').join()}';
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(player.displayName),
                  subtitle: icons.isEmpty ? null : Text(icons),
                  trailing: Text('${minutes[player.id] ?? 0} min'),
                );
              }),
          ],
        ),
      ),
    );
  }
}
