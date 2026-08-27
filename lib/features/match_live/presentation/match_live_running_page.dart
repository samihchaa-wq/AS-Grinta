import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/match_live/domain/match_live_event.dart';
import 'package:as_grinta/features/match_live/domain/match_live_formation.dart';
import 'package:as_grinta/features/match_live/domain/match_live_session.dart';
import 'package:as_grinta/features/match_live/domain/match_live_state_bundle.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_recap_page.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/live_bench_tile.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/live_substitution_line.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/match_live_clock.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/match_live_scorer_picker_dialog.dart';
import 'package:as_grinta/features/matches/presentation/widgets/upcoming_match_fixture_header.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/formation_pitch_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'match_live_running_widgets.dart';

/// Un changement préparé mais pas encore envoyé.
typedef PendingSubstitution = ({String playerIn, String playerOut});

/// Le match est en cours (running/paused/halftime) ou terminé mais pas
/// encore exporté : c'est l'écran principal du Tableau Blanc.
class MatchLiveRunningPage extends ConsumerStatefulWidget {
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
  ConsumerState<MatchLiveRunningPage> createState() =>
      _MatchLiveRunningPageState();
}

class _MatchLiveRunningPageState extends ConsumerState<MatchLiveRunningPage> {
  final List<PendingSubstitution> _pending = [];
  final GlobalKey _journalKey = GlobalKey();
  bool _saving = false;
  bool _savingFormation = false;
  bool _journalExpanded = false;

  String get matchId => widget.matchId;
  MatchLiveStateBundle get bundle => widget.bundle;
  bool get canEdit => widget.canEdit;

  @override
  Widget build(BuildContext context) {
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

    final previewLineup = _previewLineup(lineup);
    final field = previewLineup.entriesFor(MatchCompositionZone.field);
    final bench = previewLineup.entriesFor(MatchCompositionZone.bench);
    final scorerCandidates = [...field, ...bench];
    final pendingOutIds = {for (final pair in _pending) pair.playerOut};
    final controller = ref.read(matchLiveStateProvider(matchId).notifier);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.liveScreenGutter,
        AppSpacing.sectionGap,
        AppSpacing.liveScreenGutter,
        32,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _LiveTopBar(
          session: bundle.session,
          canEdit: canEdit,
          onPause: () => controller.setClockState('pause'),
          onResume: () => controller.setClockState('resume'),
          onResumeSecondHalf: () =>
              controller.setClockState('resume_second_half'),
          onHalftime: () => _confirmHalftime(context, controller),
          onRestart: () => _confirmRestart(context, controller),
          onEndMatch: () => _confirmEndMatch(context, controller),
        ),
        const SizedBox(height: 10),
        _ScoreCard(bundle: bundle, canEdit: canEdit),
        if (canEdit && _pending.isNotEmpty) ...[
          const SizedBox(height: 10),
          _PendingSubstitutions(
            pending: _pending,
            nameOf: (participantId) => _nameOf(lineup, participantId),
            busy: _saving,
            onRemove: (pair) => setState(() => _pending.remove(pair)),
            onClear: () => setState(_pending.clear),
            onValidate: () => _validatePending(lineup, controller),
          ),
        ],
        if (canEdit) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('live-formation-${lineup.formationCode}'),
            initialValue: formationForCode(lineup.formationCode).code,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Dispositif',
              border: const OutlineInputBorder(),
              helperText: _pending.isNotEmpty
                  ? 'Valide ou annule les remplacements en attente avant de '
                      'changer de dispositif.'
                  : null,
            ),
            items: [
              for (final formation in footballFormations)
                DropdownMenuItem(
                  value: formation.code,
                  child: Text(formation.code),
                ),
            ],
            onChanged: _saving || _savingFormation || _pending.isNotEmpty
                ? null
                : (value) {
                    if (value != null) {
                      _changeFormation(lineup, value, controller);
                    }
                  },
          ),
        ],
        const SizedBox(height: AppSpacing.sectionGap),
        LayoutBuilder(
          builder: (context, constraints) {
            final metrics = benchAndPitchMetrics(constraints.maxWidth);
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BenchColumn(
                    bench: bench,
                    bundle: bundle,
                    canEdit: canEdit,
                    metrics: metrics,
                    pendingOutIds: pendingOutIds,
                    onFieldPlayerDropped: (playerOut, playerIn) =>
                        _stage(playerIn: playerIn, playerOut: playerOut),
                  ),
                  const SizedBox(width: _benchGap),
                  Expanded(
                    child: FormationPitchEditor(
                      slots: formationForCode(lineup.formationCode).slots,
                      entries: field,
                      editable: canEdit,
                      finishedBenchCounts: bundle.substituteCounts,
                      markerMetrics: metrics,
                      onDroppedOnSlot: (moving, slot) => _handlePitchDrop(
                        context,
                        controller,
                        lineup,
                        moving,
                        slot,
                      ),
                      onRemoveFromField: (entry) =>
                          _explainHowToSubstitute(context),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        _LiveJournal(
          key: _journalKey,
          events: bundle.events,
          expanded: _journalExpanded,
          canEdit: canEdit,
          onExpandedChanged: (value) =>
              setState(() => _journalExpanded = value),
          onEditScorer: (event) =>
              _pickGoalScorer(context, controller, event, scorerCandidates),
          onEditAssist: (event) =>
              _pickGoalAssist(context, controller, event, scorerCandidates),
          onDelete: (event) => _confirmDeleteEvent(context, controller, event),
        ),
      ],
    );
  }

  MatchComposition _previewLineup(MatchComposition lineup) {
    if (_pending.isEmpty) return lineup;

    final positions = {
      for (final entry in lineup.entriesFor(MatchCompositionZone.field))
        entry.participantId: Offset(entry.x ?? .5, entry.y ?? .5),
    };
    final incomingOf = {
      for (final pair in _pending) pair.playerIn: pair.playerOut,
    };
    final outgoing = {for (final pair in _pending) pair.playerOut};
    var benchOrder = lineup.entriesFor(MatchCompositionZone.bench).length;

    return lineup.copyWith(
      entries: [
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
      ],
    );
  }

  bool _isPendingParticipant(String participantId) {
    return _pending.any(
      (pair) =>
          pair.playerIn == participantId || pair.playerOut == participantId,
    );
  }

  void _stage({
    required MatchCompositionEntry playerIn,
    required MatchCompositionEntry playerOut,
  }) {
    final alreadyUsed = _pending.any(
      (pair) =>
          pair.playerIn == playerIn.participantId ||
          pair.playerOut == playerIn.participantId ||
          pair.playerIn == playerOut.participantId ||
          pair.playerOut == playerOut.participantId,
    );
    if (alreadyUsed) {
      _showMessage(
        context,
        'Ce joueur fait déjà partie des changements en attente.',
      );
      return;
    }
    setState(() {
      _pending.add((
        playerIn: playerIn.participantId,
        playerOut: playerOut.participantId,
      ));
    });
  }

  String _nameOf(MatchComposition lineup, String participantId) {
    for (final entry in lineup.entries) {
      if (entry.participantId == participantId) return entry.displayName;
    }
    return '?';
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _explainHowToSubstitute(BuildContext context) {
    _showMessage(
      context,
      'Glisse ce joueur sur le remplaçant qui entre, à gauche du terrain.',
    );
  }

  Future<void> _changeFormation(
    MatchComposition lineup,
    String formationCode,
    MatchLiveStateController controller,
  ) async {
    if (_saving || _savingFormation) return;
    if (_pending.isNotEmpty) {
      _showMessage(
        context,
        'Valide ou annule les remplacements en attente avant de changer de '
        'dispositif.',
      );
      return;
    }

    final currentCode = formationForCode(lineup.formationCode).code;
    final nextCode = formationForCode(formationCode).code;
    if (currentCode == nextCode) return;

    final changed = repositionLiveLineupForFormation(lineup, nextCode);
    setState(() => _savingFormation = true);
    try {
      await controller.changeFormation(
        formationCode: nextCode,
        entries: [
          for (final entry in changed.entries) entry.toRpcJson(),
        ],
        expectedLineupRevision: bundle.session.lineupRevision,
      );
      if (!mounted) return;
      _showMessage(context, 'Dispositif $nextCode appliqué.');
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        context,
        'Impossible de changer le dispositif. L’état Live a été resynchronisé.',
      );
    } finally {
      if (mounted) setState(() => _savingFormation = false);
    }
  }

  Future<void> _validatePending(
    MatchComposition lineup,
    MatchLiveStateController controller,
  ) async {
    if (_pending.isEmpty || _saving) return;
    final pairs = [..._pending];

    final positions = {
      for (final entry in lineup.entriesFor(MatchCompositionZone.field))
        entry.participantId: Offset(entry.x ?? .5, entry.y ?? .5),
    };
    final incomingOf = {for (final p in pairs) p.playerIn: p.playerOut};
    final outgoing = {for (final p in pairs) p.playerOut};
    var benchOrder = lineup.entriesFor(MatchCompositionZone.bench).length;

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

    setState(() => _saving = true);
    try {
      await controller.saveLiveLineup(
        entries: [for (final entry in entries) entry.toRpcJson()],
        expectedLineupRevision: bundle.session.lineupRevision,
        substitutions: pairs,
      );
      if (mounted) setState(() => _pending.clear());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickGoalScorer(
    BuildContext context,
    MatchLiveStateController controller,
    MatchLiveEvent event,
    List<MatchCompositionEntry> candidates,
  ) async {
    final choice = await pickMatchLiveScorer(
      context,
      candidates: candidates,
      title:
          'Qui a marqué à la ${AppFormats.ordinalFeminine(event.minute)} minute ?',
      extraChoiceLabel: 'CSC adverse',
      extraChoiceIcon: Icons.shield_moon_outlined,
    );
    if (choice == null) return;
    if (choice == kMatchLiveExtraChoiceId) {
      await controller.setEventScorer(event.id, isOpponentOwnGoal: true);
      return;
    }
    if (!context.mounted) return;
    // Dans la foulée du buteur, on demande le passeur : c'est le moment où le
    // coach a l'action en tête. « Aucune » est proposé en premier pour que ça
    // reste une question d'une seconde.
    final assist = await _askAssist(
      context,
      candidates: candidates,
      scorerParticipantId: choice,
      minute: event.minute,
    );
    await controller.setEventScorer(
      event.id,
      scorerParticipantId: choice,
      assistParticipantId: assist.participantId,
    );
  }

  /// Corriger la seule passe décisive, sans retoucher au buteur.
  Future<void> _pickGoalAssist(
    BuildContext context,
    MatchLiveStateController controller,
    MatchLiveEvent event,
    List<MatchCompositionEntry> candidates,
  ) async {
    final scorer = event.scorerParticipantId;
    if (scorer == null) return;
    final assist = await _askAssist(
      context,
      candidates: candidates,
      scorerParticipantId: scorer,
      minute: event.minute,
    );
    // Fermer la feuille sans choisir ne doit rien effacer.
    if (!assist.answered) return;
    await controller.setEventScorer(
      event.id,
      scorerParticipantId: scorer,
      assistParticipantId: assist.participantId,
    );
  }

  /// Renvoie le participant crédité de la passe décisive. `answered` distingue
  /// « pas de passe décisive » d'une feuille fermée sans répondre. Le buteur ne
  /// peut pas se faire la passe à lui-même.
  Future<({bool answered, String? participantId})> _askAssist(
    BuildContext context, {
    required List<MatchCompositionEntry> candidates,
    required String scorerParticipantId,
    required int minute,
  }) async {
    final choice = await pickMatchLiveScorer(
      context,
      candidates: [
        for (final entry in candidates)
          if (entry.participantId != scorerParticipantId) entry,
      ],
      title: 'Passe décisive sur le but de la '
          '${AppFormats.ordinalFeminine(minute)} minute ?',
      icon: Icons.emoji_events_outlined,
      extraChoiceLabel: 'Aucune passe décisive',
      extraChoiceIcon: Icons.block_outlined,
    );
    if (choice == null) return (answered: false, participantId: null);
    if (choice == kMatchLiveExtraChoiceId) {
      return (answered: true, participantId: null);
    }
    return (answered: true, participantId: choice);
  }

  Future<void> _confirmDeleteEvent(
    BuildContext context,
    MatchLiveStateController controller,
    MatchLiveEvent event,
  ) async {
    final description = switch (event.type) {
      MatchLiveEventType.goalUs => event.isOpponentOwnGoal
          ? "But AS Grinta (CSC adverse) · ${event.minute}'"
          : "But AS Grinta · ${event.scorerName ?? 'buteur à désigner'} · "
              "${event.minute}'",
      MatchLiveEventType.goalThem => "But adverse · ${event.minute}'",
      MatchLiveEventType.substitution => '${event.playerInName ?? '?'} entre · '
          '${event.playerOutName ?? '?'} sort · ${event.minute}\'',
    };
    final title = event.type == MatchLiveEventType.substitution
        ? 'Retirer ce remplacement ?'
        : 'Retirer ce but ?';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(description),
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
    if (confirmed == true) {
      await controller.deleteEvent(event.id);
    }
  }

  Future<void> _confirmHalftime(
    BuildContext context,
    MatchLiveStateController controller,
  ) async {
    final planned = bundle.session.planPlannedDurationMinutes;
    final target = Duration(seconds: planned * 30);
    final minutes = target.inMinutes.toString().padLeft(2, '0');
    final seconds = (target.inSeconds % 60).toString().padLeft(2, '0');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Passer à la mi-temps ?'),
        content: Text(
          'Le chronomètre sera calé sur $minutes:$seconds — la moitié des '
          '$planned minutes de jeu prévues — puis mis en pause.\n\n'
          'Le temps affiché actuellement sera donc remplacé.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Oui, mi-temps'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.setClockState('halftime');
    }
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

  Future<void> _confirmRestart(
    BuildContext context,
    MatchLiveStateController controller,
  ) async {
    final goals = bundle.ownGoals.length + bundle.opponentGoals.length;
    final substitutions = bundle.substitutions.length;
    final details = [
      if (goals > 0) goals == 1 ? '1 but' : '$goals buts',
      if (substitutions > 0)
        substitutions == 1 ? '1 remplacement' : '$substitutions remplacements',
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recommencer le match ?'),
        content: Text(
          details.isEmpty
              ? 'Le chronomètre et le score repartent à zéro, et la '
                  'composition redevient celle du coup d’envoi.\n\n'
                  'Cette action est définitive.'
              : 'Tout ce qui a été saisi sera effacé : ${details.join(' et ')}, '
                  'le chronomètre et le score.\n\n'
                  'La composition redevient celle du coup d’envoi et tu '
                  'reviens à l’écran de préparation.\n\n'
                  'Cette action est définitive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Tout effacer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(_pending.clear);
    await controller.restartSession();
  }

  Future<void> _handlePitchDrop(
    BuildContext context,
    MatchLiveStateController controller,
    MatchComposition lineup,
    MatchCompositionEntry moving,
    FootballFormationSlot slot,
  ) async {
    if (_isPendingParticipant(moving.participantId)) {
      _showMessage(
        context,
        'Valide ou annule ce changement avant de déplacer ce joueur.',
      );
      return;
    }

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

    if (currentAtSlot != null &&
        _isPendingParticipant(currentAtSlot.participantId)) {
      _showMessage(
        context,
        'Cette position fait déjà partie d’un changement en attente.',
      );
      return;
    }

    if (moving.zone != MatchCompositionZone.field) {
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
      _stage(playerIn: moving, playerOut: currentAtSlot);
      return;
    }

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
      expectedLineupRevision: bundle.session.lineupRevision,
    );
  }
}
