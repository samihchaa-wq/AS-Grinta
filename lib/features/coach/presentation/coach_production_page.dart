import 'package:as_grinta/features/coach/domain/coach_board.dart';
import 'package:as_grinta/features/coach/presentation/coach_board_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CoachProductionPage extends ConsumerWidget {
  const CoachProductionPage({super.key});

  String _clock(int seconds) {
    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${remaining.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(coachBoardControllerProvider);
    final controller = ref.read(coachBoardControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tableau du coach'),
        actions: [
          if (state.canEdit)
            IconButton(
              tooltip: 'Ajouter un invité du match',
              onPressed: () => _addGuest(context, ref),
              icon: const Icon(Icons.person_add_alt_1),
            ),
          Center(
            child: Text(
              _clock(state.elapsedSeconds),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(coachBoardControllerProvider);
          await Future<void>.delayed(const Duration(milliseconds: 400));
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          children: [
            if (state.error != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(state.error!),
                ),
              ),
            _ScoreControls(state: state, controller: controller),
            const SizedBox(height: 12),
            if (state.canEdit && !state.isRunning)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.edit_note_outlined),
                  title: Text('Préparation du match'),
                  subtitle: Text(
                    'La composition et les invités sont modifiables. '
                    'Les buts et remplacements seront disponibles après Démarrer.',
                  ),
                ),
              ),
            const SizedBox(height: 12),
            _Pitch(state: state, controller: controller),
            const SizedBox(height: 12),
            _Bench(state: state, controller: controller),
            const SizedBox(height: 12),
            _EventControls(state: state, controller: controller),
            const SizedBox(height: 12),
            _Timeline(state: state, controller: controller),
          ],
        ),
      ),
    );
  }

  Future<void> _addGuest(BuildContext context, WidgetRef ref) async {
    final state = ref.read(coachBoardControllerProvider);
    final nameController = TextEditingController();
    var isGoalkeeper = false;
    String? selectedSlot = state.formationSlots
        .where((slot) => !state.lineup.containsKey(slot))
        .firstOrNull;
    selectedSlot ??= 'bench';
    String? error;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Invité du match'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'L’invité existe uniquement pour ce match. '
                  'Ses buts et passes restent visibles dans le direct, '
                  'sans statistique permanente.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nom ou surnom *',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedSlot,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Placement'),
                  items: [
                    ...state.formationSlots.map(
                      (slot) => DropdownMenuItem(
                        value: slot,
                        child: Text(slot.toUpperCase()),
                      ),
                    ),
                    const DropdownMenuItem(
                      value: 'bench',
                      child: Text('Banc'),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => selectedSlot = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Gardien invité'),
                  value: isGoalkeeper,
                  onChanged: (value) =>
                      setDialogState(() => isGoalkeeper = value),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
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
                if (nameController.text.trim().isEmpty || selectedSlot == null) {
                  setDialogState(() => error = 'Renseigne un nom et un placement.');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );

    if (accepted == true && selectedSlot != null) {
      await ref
          .read(coachBoardControllerProvider.notifier)
          .addExceptionalPlayer(
            name: nameController.text,
            isGoalkeeper: isGoalkeeper,
            slotCode: selectedSlot!,
          );
    }
    nameController.dispose();
  }
}

class _ScoreControls extends StatelessWidget {
  const _ScoreControls({required this.state, required this.controller});

  final CoachBoardState state;
  final CoachBoardController controller;

  Future<bool> _confirm(BuildContext context, String title, String message) {
    return showDialog<bool>(
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
            child: const Text('Confirmer'),
          ),
        ],
      ),
    ).then((value) => value ?? false);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                const Text('—', style: TextStyle(fontSize: 28)),
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
            if (state.canEdit) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: state.isRunning
                      ? controller.pauseTimer
                      : controller.startTimer,
                  icon: Icon(state.isRunning ? Icons.pause : Icons.play_arrow),
                  label: Text(state.isRunning ? 'Pause' : 'Démarrer le match'),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: !state.isRunning
                        ? null
                        : () async {
                            if (await _confirm(
                              context,
                              'Mi-temps',
                              'Mettre le chrono en pause à la mi-temps ?',
                            )) {
                              await controller.goToHalfTime();
                            }
                          },
                    child: const Text('Mi-temps'),
                  ),
                  OutlinedButton(
                    onPressed: !state.isRunning
                        ? null
                        : () async {
                            if (await _confirm(
                              context,
                              'Fin du match',
                              'Terminer le match sur le score '
                                  '${state.scoreUs}-${state.scoreThem} ?',
                            )) {
                              await controller.endMatch();
                            }
                          },
                    child: const Text('Fin du match'),
                  ),
                  OutlinedButton(
                    onPressed: state.isRunning
                        ? null
                        : () async {
                            if (await _confirm(
                              context,
                              'Réinitialiser',
                              'Effacer la composition, le chrono et les événements ?',
                            )) {
                              await controller.resetBoard();
                            }
                          },
                    child: const Text('Réinitialiser'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pitch extends StatelessWidget {
  const _Pitch({required this.state, required this.controller});

  final CoachBoardState state;
  final CoachBoardController controller;

  String _icons(String playerId) {
    final player = state.playerById(playerId);
    if (player?.isGoalkeeper == true) return '';
    final goals = state.events
        .where((event) =>
            event.type == CoachEventType.goalUs && event.playerId == playerId)
        .length;
    final assists = state.events
        .where((event) => event.assistPlayerId == playerId)
        .length;
    return '${List.filled(goals, '⚽').join()}'
        '${List.filled(assists, '👟').join()}';
  }

  Future<void> _pick(BuildContext context, String slot) async {
    if (!state.canEdit) return;
    final used = state.lineup.values.toSet();
    final current = state.lineup[slot];
    final available = state.players
        .where((player) => player.id == current || !used.contains(player.id))
        .toList();
    final id = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: available
              .map(
                (player) => ListTile(
                  leading: CircleAvatar(child: Text(player.initials)),
                  title: Text(player.displayName),
                  subtitle: player.isGuest
                      ? const Text('Invité du match')
                      : null,
                  onTap: () => Navigator.pop(sheetContext, player.id),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (id != null) await controller.movePlayer(id, slot);
  }

  @override
  Widget build(BuildContext context) {
    final positions = computeFormationPositions(
      state.formationCode,
      state.formationSlots,
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 0.72,
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _PitchPainter())),
              ...state.formationSlots.map((slot) {
                final position = positions[slot] ?? const Offset(.5, .5);
                final player = state.playerById(state.lineup[slot]);
                return Positioned(
                  left: position.dx * constraints.maxWidth - 31,
                  top: position.dy * constraints.maxHeight - 31,
                  child: InkWell(
                    onTap: state.canEdit ? () => _pick(context, slot) : null,
                    borderRadius: BorderRadius.circular(40),
                    child: SizedBox(
                      width: 62,
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 25,
                            backgroundColor: player?.isGoalkeeper == true
                                ? Colors.orange
                                : const Color(0xFF126B3A),
                            child: Text(player?.initials ?? '+'),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            color: Colors.black87,
                            child: Text(
                              player == null
                                  ? slot.toUpperCase()
                                  : '${player.displayName} ${_icons(player.id)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bench extends StatelessWidget {
  const _Bench({required this.state, required this.controller});

  final CoachBoardState state;
  final CoachBoardController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Banc (${state.bench.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: state.bench.map((id) {
                final player = state.playerById(id);
                return ActionChip(
                  avatar: CircleAvatar(child: Text(player?.initials ?? '?')),
                  label: Text(
                    player == null
                        ? 'Joueur'
                        : '${player.displayName}'
                            '${player.isGuest ? ' · Invité' : ''}',
                  ),
                  onPressed: state.canEdit
                      ? () async {
                          final emptySlot = state.formationSlots
                              .where((slot) => !state.lineup.containsKey(slot))
                              .firstOrNull;
                          if (emptySlot != null) {
                            await controller.movePlayer(id, emptySlot);
                          }
                        }
                      : null,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventControls extends StatelessWidget {
  const _EventControls({required this.state, required this.controller});

  final CoachBoardState state;
  final CoachBoardController controller;

  Future<void> _goal(BuildContext context) async {
    String? scorer;
    String? assist;
    final players = state.lineup.values
        .map(state.playerById)
        .whereType<CoachPlayer>()
        .where((player) => !player.isGoalkeeper)
        .toList();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('But AS Grinta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Buteur'),
                items: players
                    .map(
                      (player) => DropdownMenuItem(
                        value: player.id,
                        child: Text(player.displayName),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() {
                  scorer = value;
                  if (assist == scorer) assist = null;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Passeur (facultatif)',
                ),
                items: players
                    .where((player) => player.id != scorer)
                    .map(
                      (player) => DropdownMenuItem(
                        value: player.id,
                        child: Text(player.displayName),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => assist = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: scorer == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      await controller.addGoalUs(scorerId: scorer, assistId: assist);
    }
  }

  Future<void> _substitution(BuildContext context) async {
    String? playerOut;
    String? playerIn;
    final field = state.lineup.values
        .map(state.playerById)
        .whereType<CoachPlayer>()
        .toList();
    final bench = state.bench
        .map(state.playerById)
        .whereType<CoachPlayer>()
        .toList();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Remplacement'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Sortant'),
                items: field
                    .map(
                      (player) => DropdownMenuItem(
                        value: player.id,
                        child: Text(player.displayName),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => playerOut = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Entrant'),
                items: bench
                    .map(
                      (player) => DropdownMenuItem(
                        value: player.id,
                        child: Text(player.displayName),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => playerIn = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: playerOut == null || playerIn == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Valider'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      await controller.addSubstitution(
        inPlayerId: playerIn!,
        outPlayerId: playerOut!,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!state.canEdit) return const SizedBox.shrink();
    if (!state.isRunning) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.lock_clock_outlined),
          title: Text('Événements verrouillés'),
          subtitle: Text(
            'Démarre le match pour saisir les buts et remplacements.',
          ),
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: () => _goal(context),
          icon: const Icon(Icons.sports_soccer),
          label: const Text('But Grinta'),
        ),
        OutlinedButton.icon(
          onPressed: controller.addGoalThem,
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('But adverse'),
        ),
        OutlinedButton.icon(
          onPressed: state.lineup.isEmpty || state.bench.isEmpty
              ? null
              : () => _substitution(context),
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Remplacement'),
        ),
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.state, required this.controller});

  final CoachBoardState state;
  final CoachBoardController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Événements', style: Theme.of(context).textTheme.titleMedium),
            if (state.events.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Aucun événement.'),
              )
            else
              ...state.events.reversed.map((event) {
                final scorer = state.playerById(event.playerId);
                final assist = state.playerById(event.assistPlayerId);
                final playerIn = state.playerById(event.playerInId);
                final playerOut = state.playerById(event.playerOutId);
                final label = switch (event.type) {
                  CoachEventType.goalUs =>
                    '⚽ ${scorer?.displayName ?? 'Buteur'}'
                        '${assist == null ? '' : ' · 👟 ${assist.displayName}'}',
                  CoachEventType.goalThem => '⚽ But adversaire',
                  CoachEventType.substitution =>
                    '🔁 ${playerOut?.displayName ?? 'Joueur'} → '
                        '${playerIn?.displayName ?? 'Joueur'}',
                  _ => event.type.label,
                };
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Text("${event.minute}'")),
                  title: Text(label),
                  trailing: state.canEdit && state.isRunning
                      ? IconButton(
                          tooltip: 'Supprimer cet événement',
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

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF176B3A),
    );
    final line = Paint()
      ..color = Colors.white70
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final rect = Rect.fromLTWH(14, 14, size.width - 28, size.height - 28);
    canvas.drawRect(rect, line);
    canvas.drawLine(
      Offset(14, size.height / 2),
      Offset(size.width - 14, size.height / 2),
      line,
    );
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width * .16,
      line,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
