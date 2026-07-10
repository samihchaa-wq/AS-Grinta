import 'package:as_grinta/features/coach/domain/coach_board.dart';
import 'package:as_grinta/features/coach/presentation/coach_board_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CoachProductionPage extends ConsumerWidget {
  const CoachProductionPage({super.key});

  String _clock(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(coachBoardControllerProvider);
    final ctrl = ref.read(coachBoardControllerProvider.notifier);

    if (state.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tableau du coach'),
        actions: [
          Center(
            child: Text(
              _clock(state.elapsedSeconds),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(coachBoardControllerProvider),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (!state.canEdit)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.visibility_outlined),
                  title: Text('Lecture seule'),
                  subtitle: Text('Le staff modifie le Tableau en direct.'),
                ),
              ),
            if (state.error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(state.error!),
                ),
              ),
            _ScoreControls(state: state, ctrl: ctrl),
            const SizedBox(height: 12),
            _Pitch(state: state, ctrl: ctrl),
            const SizedBox(height: 12),
            _Bench(state: state, ctrl: ctrl),
            const SizedBox(height: 12),
            _EventControls(state: state, ctrl: ctrl),
            const SizedBox(height: 12),
            _Timeline(state: state, ctrl: ctrl),
            const SizedBox(height: 12),
            _MinutesPlayed(state: state),
          ],
        ),
      ),
    );
  }
}

class _ScoreControls extends StatelessWidget {
  const _ScoreControls({required this.state, required this.ctrl});
  final CoachBoardState state;
  final CoachBoardController ctrl;

  Future<bool> _confirm(BuildContext context, String title, String body) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirmer'),
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
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text('AS Grinta'),
                      Text('${state.scoreUs}',
                          style: Theme.of(context).textTheme.displaySmall),
                    ],
                  ),
                ),
                const Text('—', style: TextStyle(fontSize: 28)),
                Expanded(
                  child: Column(
                    children: [
                      const Text('Adversaire'),
                      Text('${state.scoreThem}',
                          style: Theme.of(context).textTheme.displaySmall),
                    ],
                  ),
                ),
              ],
            ),
            if (state.canEdit) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: state.lineup.length != 11
                        ? null
                        : state.isRunning
                            ? ctrl.pauseTimer
                            : ctrl.startTimer,
                    icon: Icon(state.isRunning ? Icons.pause : Icons.play_arrow),
                    label: Text(state.isRunning ? 'Pause' : 'Démarrer'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      if (await _confirm(context, 'Mi-temps',
                          'Arrêter le chrono et passer à la mi-temps ?')) {
                        await ctrl.goToHalfTime();
                      }
                    },
                    child: const Text('Mi-temps'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      if (await _confirm(context, 'Fin du match',
                          'Terminer le match sur le score ${state.scoreUs}-${state.scoreThem} ?')) {
                        await ctrl.endMatch();
                      }
                    },
                    child: const Text('Fin du match'),
                  ),
                  OutlinedButton(
                    onPressed: state.isRunning
                        ? null
                        : () async {
                            if (await _confirm(context, 'Réinitialiser',
                                'Effacer la composition, le score, le chrono et les événements ?')) {
                              await ctrl.resetBoard();
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
  const _Pitch({required this.state, required this.ctrl});
  final CoachBoardState state;
  final CoachBoardController ctrl;

  String _icons(String playerId) {
    final player = state.playerById(playerId);
    if (player?.isGoalkeeper == true || player?.isGuest == true) return '';
    final goals = state.events
        .where((e) => e.type == CoachEventType.goalUs && e.playerId == playerId)
        .length;
    final assists = state.events.where((e) => e.assistPlayerId == playerId).length;
    return '${List.filled(goals, '⚽').join()}${List.filled(assists, '👟').join()}';
  }

  Future<void> _pick(BuildContext context, String slot) async {
    if (!state.canEdit) return;
    final used = state.lineup.values.toSet();
    final current = state.lineup[slot];
    final available = state.players
        .where((p) => p.id == current || !used.contains(p.id))
        .toList();
    final id = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: available
              .map((p) => ListTile(
                    leading: CircleAvatar(child: Text(p.initials)),
                    title: Text(p.name),
                    subtitle: Text(_icons(p.id)),
                    onTap: () => Navigator.pop(ctx, p.id),
                  ))
              .toList(),
        ),
      ),
    );
    if (id != null) await ctrl.movePlayer(id, slot);
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
          builder: (context, c) => Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _PitchPainter())),
              ...state.formationSlots.map((slot) {
                final pos = positions[slot] ?? const Offset(.5, .5);
                final player = state.playerById(state.lineup[slot]);
                return Positioned(
                  left: pos.dx * c.maxWidth - 31,
                  top: pos.dy * c.maxHeight - 31,
                  child: InkWell(
                    onTap: () => _pick(context, slot),
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
                                horizontal: 4, vertical: 2),
                            color: Colors.black87,
                            child: Text(
                              player == null
                                  ? slot.toUpperCase()
                                  : '${player.displayName} ${_icons(player.id)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 9),
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
  const _Bench({required this.state, required this.ctrl});
  final CoachBoardState state;
  final CoachBoardController ctrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Banc (${state.bench.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: state.bench.map((id) {
                final p = state.playerById(id);
                return ActionChip(
                  avatar: CircleAvatar(child: Text(p?.initials ?? '?')),
                  label: Text(p == null
                      ? 'Joueur'
                      : '${p.displayName}${p.isGuest ? ' · Invité' : ''}'),
                  onPressed: state.canEdit
                      ? () async {
                          final emptySlot = state.formationSlots
                              .where((s) => !state.lineup.containsKey(s))
                              .firstOrNull;
                          if (emptySlot != null) {
                            await ctrl.movePlayer(id, emptySlot);
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
  const _EventControls({required this.state, required this.ctrl});
  final CoachBoardState state;
  final CoachBoardController ctrl;

  Future<void> _goal(BuildContext context) async {
    String? scorer;
    String? assist;
    final players = state.lineup.values
        .map(state.playerById)
        .whereType<CoachPlayer>()
        .where((player) => !player.isGuest && !player.isGoalkeeper)
        .toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setState) => AlertDialog(
          title: const Text('But AS Grinta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Buteur'),
                items: players
                    .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                    .toList(),
                onChanged: (v) => setState(() {
                  scorer = v;
                  if (assist == scorer) assist = null;
                }),
              ),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Passeur'),
                items: players
                    .where((p) => p.id != scorer)
                    .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                    .toList(),
                onChanged: (v) => setState(() => assist = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: scorer == null ? null : () => Navigator.pop(ctx, true),
                child: const Text('Ajouter')),
          ],
        ),
      ),
    );
    if (ok == true) await ctrl.addGoalUs(scorerId: scorer, assistId: assist);
  }

  Future<void> _sub(BuildContext context) async {
    String? outId;
    String? inId;
    final field = state.lineup.values
        .map(state.playerById)
        .whereType<CoachPlayer>()
        .toList();
    final bench = state.bench.map(state.playerById).whereType<CoachPlayer>().toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setState) => AlertDialog(
          title: const Text('Remplacement'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Sortant'),
                items: field
                    .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                    .toList(),
                onChanged: (v) => setState(() => outId = v),
              ),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Entrant'),
                items: bench
                    .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                    .toList(),
                onChanged: (v) => setState(() => inId = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: outId == null || inId == null
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: const Text('Valider')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await ctrl.addSubstitution(inPlayerId: inId!, outPlayerId: outId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!state.canEdit) return const SizedBox.shrink();
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
          onPressed: ctrl.addGoalThem,
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('But adverse'),
        ),
        OutlinedButton.icon(
          onPressed: state.lineup.isEmpty || state.bench.isEmpty
              ? null
              : () => _sub(context),
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Remplacement'),
        ),
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.state, required this.ctrl});
  final CoachBoardState state;
  final CoachBoardController ctrl;

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
              ...state.events.reversed.map((e) {
                final scorer = state.playerById(e.playerId);
                final assist = state.playerById(e.assistPlayerId);
                final pIn = state.playerById(e.playerInId);
                final pOut = state.playerById(e.playerOutId);
                final label = switch (e.type) {
                  CoachEventType.goalUs =>
                    '⚽ ${scorer?.displayName ?? 'Buteur'}${assist == null ? '' : ' · 👟 ${assist.displayName}'}',
                  CoachEventType.goalThem => '⚽ But adversaire',
                  CoachEventType.substitution =>
                    '🔁 ${pOut?.displayName ?? 'Joueur'} → ${pIn?.displayName ?? 'Joueur'}',
                  _ => e.type.label,
                };
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Text("${e.minute}'")),
                  title: Text(label),
                  trailing: state.canEdit
                      ? IconButton(
                          onPressed: () => ctrl.removeEvent(e.id),
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

class _MinutesPlayed extends StatelessWidget {
  const _MinutesPlayed({required this.state});
  final CoachBoardState state;

  Map<String, int> _compute() {
    final now =
        (state.elapsedSeconds ~/ 60).clamp(0, state.plannedDurationMinutes);
    final subs = state.events
        .where((e) => e.type == CoachEventType.substitution)
        .toList()
      ..sort((a, b) => a.minute.compareTo(b.minute));
    final starters = state.lineup.values.toSet();
    for (final e in subs.reversed) {
      if (e.playerInId != null) starters.remove(e.playerInId);
      if (e.playerOutId != null) starters.add(e.playerOutId!);
    }
    final entered = <String, int>{for (final id in starters) id: 0};
    final total = <String, int>{};
    for (final e in subs) {
      final minute = e.minute.clamp(0, now);
      if (e.playerOutId != null) {
        final start = entered.remove(e.playerOutId) ?? 0;
        total[e.playerOutId!] =
            (total[e.playerOutId!] ?? 0) + minute - start;
      }
      if (e.playerInId != null) entered[e.playerInId!] = minute;
    }
    for (final item in entered.entries) {
      total[item.key] = (total[item.key] ?? 0) + now - item.value;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _compute();
    final players = state.players
        .where((p) => !p.isGuest && minutes.containsKey(p.id))
        .toList()
      ..sort((a, b) => minutes[b.id]!.compareTo(minutes[a.id]!));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Temps de jeu', style: Theme.of(context).textTheme.titleMedium),
            if (players.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Aucune minute calculée.'),
              )
            else
              ...players.map((p) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.name),
                    trailing: Text('${minutes[p.id]} min'),
                  )),
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
        Offset.zero & size, Paint()..color = const Color(0xFF176B3A));
    final line = Paint()
      ..color = Colors.white70
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final rect = Rect.fromLTWH(14, 14, size.width - 28, size.height - 28);
    canvas.drawRect(rect, line);
    canvas.drawLine(Offset(14, size.height / 2),
        Offset(size.width - 14, size.height / 2), line);
    canvas.drawCircle(
        Offset(size.width / 2, size.height / 2), size.width * .16, line);
    canvas.drawRect(
        Rect.fromCenter(
            center: Offset(size.width / 2, 14),
            width: size.width * .55,
            height: size.height * .2),
        line);
    canvas.drawRect(
        Rect.fromCenter(
            center: Offset(size.width / 2, size.height - 14),
            width: size.width * .55,
            height: size.height * .2),
        line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
