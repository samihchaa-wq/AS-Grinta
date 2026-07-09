import 'package:as_grinta/features/coach/presentation/coach_board_controller.dart';
import 'package:as_grinta/features/coach/presentation/coach_production_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CoachPage extends ConsumerWidget {
  const CoachPage({super.key});

  static const _noMatchMessage = 'Aucun match à venir ou en cours.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(coachBoardControllerProvider);

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
                  'Il ne sera pas ajouté au registre et ne générera aucune statistique.',
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
