import 'package:as_grinta/features/match_live/domain/match_live_event.dart';
import 'package:as_grinta/features/match_live/domain/match_live_session.dart';
import 'package:as_grinta/features/match_live/domain/match_live_state_bundle.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_recap_page.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/live_bench_tile.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/live_substitution_line.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/match_live_batch_substitution_sheet.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/match_live_clock.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/match_live_scorer_picker_dialog.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/match_live_substitution_dialog.dart';
import 'package:as_grinta/features/matches/presentation/widgets/upcoming_match_fixture_header.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/formation_pitch_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Le match est en cours (running/paused/halftime) ou terminé mais pas
/// encore exporté : c'est l'écran principal du Tableau Blanc.
class MatchLiveRunningPage extends ConsumerWidget {
  const MatchLiveRunningPage({
    super.key,
    required this.matchId,
    required this.bundle,
    required this.canEdit,
  });

  final String matchId;
  final MatchLiveStateBundle bundle;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (bundle.session.state == MatchLiveState.finished) {
      if (!canEdit) {
        return const _Message(
          message: 'Le match est terminé. En attente de la publication du '
              'compte rendu par le coach.',
        );
      }
      return MatchLiveRecapPage(matchId: matchId, bundle: bundle);
    }

    final lineup = bundle.lineup;
    if (lineup == null) {
      return const _Message(message: 'Composition indisponible.');
    }
    final field = lineup.entriesFor(MatchCompositionZone.field);
    final bench = lineup.entriesFor(MatchCompositionZone.bench);
    final scorerCandidates = [...field, ...bench];
    final controller = ref.read(
      matchLiveStateProvider(matchId).notifier,
    );

    // Cette liste est déjà imbriquée dans le scroll de la page qui l'affiche.
    // Sans shrinkWrap + NeverScrollableScrollPhysics, les deux listes se
    // disputent les gestes tactiles : scroll bloqué et glisser-déposer
    // capturé par le mauvais niveau.
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        MatchLiveClock(session: bundle.session),
        const SizedBox(height: 12),
        if (canEdit)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (bundle.session.state == MatchLiveState.running)
                OutlinedButton.icon(
                  onPressed: () => controller.setClockState('pause'),
                  icon: const Icon(Icons.pause_rounded),
                  label: const Text('Pause'),
                ),
              if (bundle.session.state == MatchLiveState.paused)
                OutlinedButton.icon(
                  onPressed: () => controller.setClockState('resume'),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Reprendre'),
                ),
              if (bundle.session.half == 1 &&
                  bundle.session.state != MatchLiveState.halftime)
                OutlinedButton.icon(
                  onPressed: () => controller.setClockState('halftime'),
                  icon: const Icon(Icons.sports_rounded),
                  label: const Text('Mi-temps'),
                ),
              if (bundle.session.state == MatchLiveState.halftime)
                FilledButton.icon(
                  onPressed: () =>
                      controller.setClockState('resume_second_half'),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Reprendre la 2ᵉ mi-temps'),
                ),
              OutlinedButton.icon(
                onPressed: () => _confirmEndMatch(context, controller),
                icon: const Icon(Icons.flag_rounded),
                label: const Text('Fin du match'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
        const SizedBox(height: 20),
        _ScoreRow(
          bundle: bundle,
          canEdit: canEdit,
          scorerCandidates: scorerCandidates,
        ),
        const SizedBox(height: 20),
        Center(
          child: FormationPitchEditor(
            slots: formationForCode(lineup.formationCode).slots,
            entries: field,
            editable: canEdit,
            finishedBenchCounts: bundle.substituteCounts,
            onDroppedOnSlot: (moving, slot) => _handlePitchDrop(
              context,
              controller,
              lineup,
              moving,
              slot,
            ),
            onRemoveFromField: (entry) =>
                _pickReplacement(context, controller, lineup, entry),
          ),
        ),
        const SizedBox(height: 14),
        DragTarget<MatchCompositionEntry>(
          onWillAcceptWithDetails: (details) =>
              canEdit && details.data.zone == MatchCompositionZone.field,
          onAcceptWithDetails: (details) =>
              _pickReplacement(context, controller, lineup, details.data),
          builder: (context, candidates, rejected) => Card(
            color: candidates.isNotEmpty
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Banc (${bench.length})',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                      ),
                      if (canEdit && bench.isNotEmpty && field.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => _pickBatch(
                            context,
                            controller,
                            lineup,
                          ),
                          icon: const Icon(Icons.swap_horiz_rounded),
                          label: const Text('Plusieurs'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (bench.isEmpty)
                    const Text('Aucun joueur sur le banc.')
                  else
                    Wrap(
                      spacing: 12,
                      runSpacing: 14,
                      children: [
                        for (final entry in bench)
                          LiveBenchTile(
                            entry: entry,
                            draggable: canEdit,
                            timesBenched:
                                bundle.timesBenched(entry.participantId),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _EventsSection(
          title: 'Remplacements',
          icon: Icons.swap_horiz_rounded,
          events: bundle.substitutions,
          emptyLabel: 'Aucun remplacement pour le moment.',
          lineBuilder: (event) => LiveSubstitutionLine.describe(
            playerInName: event.playerInName ?? '?',
            playerOutName: event.playerOutName ?? '?',
            trailingText: "${event.minute}'",
          ),
          contentBuilder: (event) => LiveSubstitutionLine(
            playerInName: event.playerInName ?? '?',
            playerOutName: event.playerOutName ?? '?',
            trailingText: "${event.minute}'",
          ),
          canEdit: canEdit,
          deleteConfirmation: 'Retirer ce remplacement ?',
          onDelete: (event) => controller.deleteEvent(event.id),
        ),
        const SizedBox(height: 12),
        _EventsSection(
          title: 'Buteurs',
          icon: Icons.sports_soccer_rounded,
          events: bundle.ownGoals,
          emptyLabel: 'Aucun but AS Grinta pour le moment.',
          lineBuilder: (event) => _goalLabel(event),
          contentBuilder: (event) => _GoalLine(
            event: event,
            canEdit: canEdit,
            onPickScorer: () => _pickGoalScorer(
              context,
              controller,
              event,
              scorerCandidates,
            ),
          ),
          canEdit: canEdit,
          deleteConfirmation: 'Retirer ce but ?',
          onDelete: (event) => controller.deleteEvent(event.id),
        ),
      ],
    );
  }

  static String _goalLabel(MatchLiveEvent event) {
    final who = event.isOpponentOwnGoal
        ? 'CSC adverse'
        : (event.scorerName ?? 'Buteur à désigner');
    return "$who · ${event.minute}'";
  }

  /// Attribue un but déjà compté : un joueur, ou un CSC adverse.
  Future<void> _pickGoalScorer(
    BuildContext context,
    MatchLiveStateController controller,
    MatchLiveEvent event,
    List<MatchCompositionEntry> candidates,
  ) async {
    final choice = await pickMatchLiveScorer(
      context,
      candidates: candidates,
      title: "Qui a marqué à la ${event.minute}ᵉ minute ?",
      extraChoiceLabel: 'CSC adverse',
      extraChoiceIcon: Icons.shield_moon_outlined,
    );
    if (choice == null) return;
    if (choice == kMatchLiveExtraChoiceId) {
      await controller.setEventScorer(event.id, isOpponentOwnGoal: true);
      return;
    }
    await controller.setEventScorer(event.id, scorerParticipantId: choice);
  }

  Future<void> _confirmEndMatch(
    BuildContext context,
    MatchLiveStateController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fin du match'),
        content: const Text('Êtes-vous sûr de vouloir finir le match ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Oui, terminer'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.endMatch();
    }
  }

  Future<void> _handlePitchDrop(
    BuildContext context,
    MatchLiveStateController controller,
    MatchComposition lineup,
    MatchCompositionEntry moving,
    FootballFormationSlot slot,
  ) async {
    final currentAtSlot = lineup.entries
        .where((entry) => entry.zone == MatchCompositionZone.field)
        .cast<MatchCompositionEntry?>()
        .firstWhere(
          (entry) =>
              entry != null &&
              (Offset(entry.x ?? .5, entry.y ?? .5) - slot.position).distance <
                  .12,
          orElse: () => null,
        );

    if (moving.zone != MatchCompositionZone.field) {
      // Entrée depuis le banc : il faut un joueur déjà sur le terrain à
      // remplacer.
      if (currentAtSlot == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Dépose ce joueur sur un titulaire déjà sur le terrain pour '
              'faire une entrée.',
            ),
          ),
        );
        return;
      }
      await _performSubstitution(
        context,
        controller,
        lineup,
        playerIn: moving,
        playerOut: currentAtSlot,
        playerInX: slot.position.dx,
        playerInY: slot.position.dy,
      );
      return;
    }

    // Repositionnement pur (terrain -> terrain), aucun événement.
    final oldPosition = Offset(moving.x ?? .5, moving.y ?? .5);
    final entries = [
      for (final entry in lineup.entries)
        if (entry.participantId == moving.participantId)
          entry.moveTo(
            MatchCompositionZone.field,
            x: slot.position.dx,
            y: slot.position.dy,
          )
        else if (currentAtSlot != null &&
            entry.participantId == currentAtSlot.participantId)
          entry.moveTo(
            MatchCompositionZone.field,
            x: oldPosition.dx,
            y: oldPosition.dy,
          )
        else
          entry,
    ];
    await controller.saveLiveLineup(
      entries: [for (final entry in entries) entry.toRpcJson()],
    );
  }

  Future<void> _pickReplacement(
    BuildContext context,
    MatchLiveStateController controller,
    MatchComposition lineup,
    MatchCompositionEntry fieldEntry,
  ) async {
    final bench = lineup.entriesFor(MatchCompositionZone.bench);
    if (bench.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Aucun remplaçant disponible sur le banc.')),
      );
      return;
    }
    final replacementId = await pickMatchLiveScorer(
      context,
      candidates: bench,
      title: 'Qui entre à la place de ${fieldEntry.displayName} ?',
      icon: Icons.arrow_upward_rounded,
    );
    if (replacementId == null) return;
    if (!context.mounted) return;
    final replacement = bench.firstWhere(
      (entry) => entry.participantId == replacementId,
    );
    await _performSubstitution(
      context,
      controller,
      lineup,
      playerIn: replacement,
      playerOut: fieldEntry,
      playerInX: fieldEntry.x ?? .5,
      playerInY: fieldEntry.y ?? .5,
    );
  }

  Future<void> _performSubstitution(
    BuildContext context,
    MatchLiveStateController controller,
    MatchComposition lineup, {
    required MatchCompositionEntry playerIn,
    required MatchCompositionEntry playerOut,
    required double playerInX,
    required double playerInY,
  }) async {
    final confirmed = await confirmMatchLiveSubstitution(
      context,
      playerInName: playerIn.displayName,
      playerOutName: playerOut.displayName,
    );
    if (!confirmed) return;

    final benchCount = lineup.entriesFor(MatchCompositionZone.bench).length;
    final entries = [
      for (final entry in lineup.entries)
        if (entry.participantId == playerIn.participantId)
          entry.moveTo(MatchCompositionZone.field, x: playerInX, y: playerInY)
        else if (entry.participantId == playerOut.participantId)
          entry.moveTo(MatchCompositionZone.bench, sortOrder: benchCount)
        else
          entry,
    ];
    await controller.saveLiveLineup(
      entries: [for (final entry in entries) entry.toRpcJson()],
      substitutions: [
        (
          playerIn: playerIn.participantId,
          playerOut: playerOut.participantId,
        ),
      ],
    );
  }

  /// Salve : plusieurs changements préparés puis envoyés d'un bloc, ce qui
  /// leur donne la même minute dans « Remplacements » et « Faits du match ».
  Future<void> _pickBatch(
    BuildContext context,
    MatchLiveStateController controller,
    MatchComposition lineup,
  ) async {
    final field = lineup.entriesFor(MatchCompositionZone.field);
    final bench = lineup.entriesFor(MatchCompositionZone.bench);
    final pairs = await pickMatchLiveSubstitutionBatch(
      context,
      field: field,
      bench: bench,
    );
    if (pairs == null || pairs.isEmpty) return;

    // Chaque entrant prend la place exacte de celui qu'il remplace.
    final positions = {
      for (final entry in field)
        entry.participantId: Offset(entry.x ?? .5, entry.y ?? .5),
    };
    final incomingOf = {
      for (final pair in pairs) pair.playerIn: pair.playerOut,
    };
    final outgoing = {for (final pair in pairs) pair.playerOut};

    var benchOrder = bench.length;
    final entries = [
      for (final entry in lineup.entries)
        if (incomingOf.containsKey(entry.participantId))
          entry.moveTo(
            MatchCompositionZone.field,
            x: positions[incomingOf[entry.participantId]]?.dx ?? .5,
            y: positions[incomingOf[entry.participantId]]?.dy ?? .5,
          )
        else if (outgoing.contains(entry.participantId))
          entry.moveTo(MatchCompositionZone.bench, sortOrder: benchOrder++)
        else
          entry,
    ];

    await controller.saveLiveLineup(
      entries: [for (final entry in entries) entry.toRpcJson()],
      substitutions: [
        for (final pair in pairs)
          (playerIn: pair.playerIn, playerOut: pair.playerOut),
      ],
    );
  }
}

class _ScoreRow extends ConsumerWidget {
  const _ScoreRow({
    required this.bundle,
    required this.canEdit,
    required this.scorerCandidates,
  });

  final MatchLiveStateBundle bundle;
  final bool canEdit;
  final List<MatchCompositionEntry> scorerCandidates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchId = bundle.session.matchId;
    final controller = ref.read(matchLiveStateProvider(matchId).notifier);
    final fixture = ref.watch(upcomingMatchFixtureProvider(matchId)).valueOrNull;

    // Le nom réel de l'adversaire, et surtout le même ordre que l'en-tête :
    // à l'extérieur, l'équipe qui reçoit est affichée à gauche.
    final opponentName = fixture?.opponentName ?? 'Adversaire';
    final grintaIsHome = fixture?.grintaIsHome ?? true;

    final grinta = _TeamScore(
      label: 'AS Grinta',
      score: bundle.session.scoreAsGrinta,
      canEdit: canEdit,
      // Aucune liste ne surgit pendant l'action : le but est compté tout de
      // suite, le buteur s'attribue depuis la ligne « Buteurs ».
      onIncrement: () => controller.adjustScore(team: 'us', delta: 1),
      onDecrement: () => controller.adjustScore(team: 'us', delta: -1),
    );
    final opponent = _TeamScore(
      label: opponentName,
      score: bundle.session.scoreAdverse,
      canEdit: canEdit,
      onIncrement: () => controller.adjustScore(team: 'them', delta: 1),
      onDecrement: () => controller.adjustScore(team: 'them', delta: -1),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(child: grintaIsHome ? grinta : opponent),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('-', style: Theme.of(context).textTheme.headlineMedium),
        ),
        Expanded(child: grintaIsHome ? opponent : grinta),
      ],
    );
  }
}

/// Une ligne de la liste « Buteurs ». Tant que le but n'est attribué à
/// personne, elle propose de choisir le buteur au lieu d'afficher un nom.
class _GoalLine extends StatelessWidget {
  const _GoalLine({
    required this.event,
    required this.canEdit,
    required this.onPickScorer,
  });

  final MatchLiveEvent event;
  final bool canEdit;
  final VoidCallback onPickScorer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final minute = "${event.minute}'";

    if (!event.needsScorer) {
      final label = event.isOpponentOwnGoal
          ? 'CSC adverse'
          : (event.scorerName ?? '?');
      return InkWell(
        onTap: canEdit ? onPickScorer : null,
        child: Row(
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 8),
            Text(minute, style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: canEdit
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onPickScorer,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                    label: const Text('Sélectionner un buteur'),
                  ),
                )
              : Text('Buteur à désigner', style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(width: 8),
        Text(minute, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _TeamScore extends StatelessWidget {
  const _TeamScore({
    required this.label,
    required this.score,
    required this.canEdit,
    required this.onIncrement,
    required this.onDecrement,
  });

  final String label;
  final int score;
  final bool canEdit;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          '$score',
          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900),
        ),
        if (canEdit)
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: score > 0 ? onDecrement : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              IconButton(
                onPressed: onIncrement,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
      ],
    );
  }
}

class _EventsSection extends StatelessWidget {
  const _EventsSection({
    required this.title,
    required this.icon,
    required this.events,
    required this.emptyLabel,
    required this.lineBuilder,
    this.contentBuilder,
    this.canEdit = false,
    this.onDelete,
    this.deleteConfirmation,
  });

  final String title;
  final IconData icon;
  final List<MatchLiveEvent> events;
  final String emptyLabel;

  /// Version texte de la ligne : confirmation de suppression, accessibilité.
  final String Function(MatchLiveEvent event) lineBuilder;

  /// Rendu enrichi de la ligne. À défaut, [lineBuilder] est affiché tel quel.
  final Widget Function(MatchLiveEvent event)? contentBuilder;
  final bool canEdit;
  final ValueChanged<MatchLiveEvent>? onDelete;

  /// Question posée avant de supprimer la ligne (« Retirer ce but ? »).
  final String? deleteConfirmation;

  Future<void> _confirmDelete(
    BuildContext context,
    MatchLiveEvent event,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(deleteConfirmation ?? 'Retirer cette ligne ?'),
        content: Text(lineBuilder(event)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirmed == true) onDelete?.call(event);
  }

  @override
  Widget build(BuildContext context) {
    final removable = canEdit && onDelete != null;
    return Card(
      child: ExpansionTile(
        leading: Icon(icon),
        title: Text('$title (${events.length})'),
        initiallyExpanded: events.isNotEmpty,
        children: [
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(emptyLabel),
            )
          else
            for (final event in events)
              ListTile(
                dense: true,
                leading: const Icon(Icons.circle, size: 8),
                title: contentBuilder?.call(event) ?? Text(lineBuilder(event)),
                trailing: removable
                    ? IconButton(
                        tooltip: 'Retirer',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => _confirmDelete(context, event),
                      )
                    : null,
              ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
