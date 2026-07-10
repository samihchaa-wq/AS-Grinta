import 'package:as_grinta/features/coach/domain/coach_board.dart';
import 'package:as_grinta/features/coach/presentation/coach_board_controller.dart';
import 'package:as_grinta/features/coach/presentation/coach_match_status_provider.dart';
import 'package:as_grinta/features/coach/presentation/coach_production_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CoachPage extends ConsumerWidget {
  const CoachPage({super.key});

  static const _noMatchMessage = 'Aucun match à venir ou en cours.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(coachBoardControllerProvider);
    final matchId = state.matchId;
    final status = matchId == null
        ? null
        : ref.watch(coachMatchStatusProvider(matchId)).valueOrNull;
    final isLocked = status != null &&
        status != 'a_venir' &&
        status != 'en_cours';

    if (state.isLoading) {
      return const Scaffold(
        appBar: _CoachAppBar(),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (state.error == _noMatchMessage) {
      return Scaffold(
        appBar: const _CoachAppBar(),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(coachBoardControllerProvider);
            await Future<void>.delayed(const Duration(milliseconds: 500));
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
            children: const [_NoMatchState()],
          ),
        ),
      );
    }

    if (isLocked) {
      return _LockedCoachView(state: state);
    }

    return Stack(
      children: [
        const CoachProductionPage(),
        if (state.canEdit)
          Positioned(
            right: 18,
            bottom: 92,
            child: FloatingActionButton.extended(
              heroTag: 'exceptional-player',
              onPressed: () => _addExceptionalPlayer(context, ref),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Invité du match'),
            ),
          ),
      ],
    );
  }

  Future<void> _addExceptionalPlayer(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final state = ref.read(coachBoardControllerProvider);
    final nameController = TextEditingController();
    var isGoalkeeper = false;
    String? selectedSlot = state.formationSlots
        .where((slot) => !state.lineup.containsKey(slot))
        .firstOrNull;
    String? error;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Ajouter un joueur exceptionnel'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ce joueur existe uniquement pour ce match et la composition. '
                  'Il ne sera pas ajouté au registre et ne générera aucune statistique permanente.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nom ou surnom *',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedSlot,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Poste'),
                  items: state.formationSlots
                      .map(
                        (slot) => DropdownMenuItem(
                          value: slot,
                          child: Text(slot.toUpperCase()),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => selectedSlot = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Gardien exceptionnel'),
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
                  setDialogState(() {
                    error = 'Renseigne un nom et un poste.';
                  });
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Ajouter à la compo'),
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

class _LockedCoachView extends StatelessWidget {
  const _LockedCoachView({required this.state});

  final CoachBoardState state;

  String _eventLabel(CoachEvent event) {
    final scorer = state.playerById(event.playerId)?.displayName;
    final assist = state.playerById(event.assistPlayerId)?.displayName;
    final playerIn = state.playerById(event.playerInId)?.displayName;
    final playerOut = state.playerById(event.playerOutId)?.displayName;
    return switch (event.type) {
      CoachEventType.goalUs =>
        '⚽ ${scorer ?? 'Buteur'}${assist == null ? '' : ' · 👟 $assist'}',
      CoachEventType.goalThem => '⚽ But adversaire',
      CoachEventType.substitution =>
        '🔁 ${playerOut ?? 'Joueur'} → ${playerIn ?? 'Joueur'}',
      _ => event.type.label,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const _CoachAppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Match terminé — Tableau verrouillé'),
              subtitle: const Text(
                'Cette vue est en lecture seule. Toute correction doit être effectuée depuis Matchs.',
              ),
              trailing: Text(
                '${state.scoreUs} - ${state.scoreThem}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Composition finale',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: state.formationSlots.map((slot) {
                final player = state.playerById(state.lineup[slot]);
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    child: Text(player?.initials ?? '?'),
                  ),
                  title: Text(player?.displayName ?? 'Poste non attribué'),
                  subtitle: Text(slot.toUpperCase()),
                  trailing: player?.isGuest == true
                      ? const Chip(label: Text('Invité'))
                      : null,
                );
              }).toList(),
            ),
          ),
          if (state.bench.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Banc final', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: state.bench.map((id) {
                  final player = state.playerById(id);
                  return ListTile(
                    dense: true,
                    title: Text(player?.displayName ?? 'Joueur'),
                    trailing: player?.isGuest == true
                        ? const Chip(label: Text('Invité'))
                        : null,
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text('Événements', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: state.events.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Aucun événement enregistré.'),
                  )
                : Column(
                    children: state.events.reversed
                        .map(
                          (event) => ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              child: Text("${event.minute}'"),
                            ),
                            title: Text(_eventLabel(event)),
                          ),
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CoachAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _CoachAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(title: const Text('Tableau du coach'));
  }
}

class _NoMatchState extends StatelessWidget {
  const _NoMatchState();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: colors.primaryContainer.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.event_available_outlined,
            size: 42,
            color: colors.primary,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Aucun match prévu',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 10),
        Text(
          'Le Tableau sera disponible dès qu’un match à venir ou en cours sera programmé.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colors.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 14),
        Text(
          'Tire vers le bas pour actualiser.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
