import 'dart:async';

import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/calendar_scoreline.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/match_live/domain/next_out_players.dart';
import 'package:as_grinta/features/match_live/domain/match_live_event.dart';
import 'package:as_grinta/features/match_live/domain/match_live_formation.dart';
import 'package:as_grinta/features/match_live/domain/match_live_session.dart';
import 'package:as_grinta/features/match_live/domain/match_live_state_bundle.dart';
import 'package:as_grinta/features/match_live/domain/substitution_salvos.dart';
import 'package:as_grinta/features/match_live/domain/time_on_field.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';
import 'package:as_grinta/features/sports_management/presentation/match_report_page.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/live_bench_tile.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/live_substitution_line.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/match_live_add_player_sheet.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/match_live_clock.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/match_live_remove_player_sheet.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/match_live_scorer_picker_dialog.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/substitution_salvo_frame.dart';
import 'package:as_grinta/features/matches/presentation/widgets/upcoming_match_fixture_header.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
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
    this.fullScreen = false,
  });

  final String matchId;
  final MatchLiveStateBundle bundle;
  final bool canEdit;

  /// Vue pilote : bandeau chrono / score et commandes en deux lignes, terrain
  /// et banc, puis buts à attribuer et changements en attente.
  final bool fullScreen;

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

  /// Rafraîchit le temps passé sur le terrain affiché à côté des prénoms
  /// pendant que le chrono tourne.
  Timer? _minuteTicker;

  @override
  void initState() {
    super.initState();
    _minuteTicker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && bundle.session.state == MatchLiveState.running) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _minuteTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (bundle.session.state == MatchLiveState.finished) {
      if (!canEdit) {
        return const _Message(
          message: 'Le match est terminé. En attente de la publication du '
              'compte rendu par le coach.',
        );
      }
      // Le Tableau Blanc est toujours posé dans une page qui défile déjà :
      // le compte rendu ne doit pas ouvrir une seconde zone de défilement.
      return MatchReportView(matchId: matchId, embedded: true);
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
    final setupControlsDisabled =
        _saving || _savingFormation || _pending.isNotEmpty;

    final pitchArea = LayoutBuilder(
      builder: (context, constraints) {
        final metrics = benchAndPitchMetrics(constraints.maxWidth);
        final lastExits = lastExitMarksByParticipant(bundle.events);
        // Prochains à sortir : calculés sur la dernière salve validée.
        // Ils restent affichés pendant la préparation de la suivante, pour
        // choisir parmi les joueurs en orange ceux qui restent à sortir.
        final nextOut = nextOutPlayers(
          field: lineup.entriesFor(MatchCompositionZone.field),
          events: bundle.events,
          substituteCounts: bundle.substituteCounts,
          benchCount: lineup.entriesFor(MatchCompositionZone.bench).length,
        );
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
                footer: widget.fullScreen && canEdit
                    ? Column(
                        children: [
                          _BenchAction(
                            icon: Icons.person_add_alt_1_rounded,
                            label: 'Ajouter',
                            tooltip: 'Ajouter un joueur',
                            onPressed: setupControlsDisabled
                                ? null
                                : () => showMatchLiveAddPlayerSheet(
                                      context,
                                      ref,
                                      matchId: matchId,
                                    ),
                          ),
                          _BenchAction(
                            icon: Icons.person_remove_rounded,
                            label: 'Retirer',
                            tooltip: 'Retirer un joueur du banc',
                            onPressed: setupControlsDisabled ||
                                    lineup
                                        .entriesFor(MatchCompositionZone.bench)
                                        .isEmpty
                                ? null
                                : () => _removeBenchPlayer(lineup, controller),
                          ),
                        ],
                      )
                    : null,
              ),
              const SizedBox(width: _benchGap),
              Expanded(
                child: FormationPitchEditor(
                  slots: formationForCode(lineup.formationCode).slots,
                  entries: field,
                  editable: canEdit,
                  finishedBenchCounts: bundle.substituteCounts,
                  benchLabels: {
                    for (final MapEntry(:key, :value)
                        in bundle.substituteCounts.entries)
                      key: liveBenchLabel(lastExits[key], value),
                  },
                  benchColors: {
                    for (final key in bundle.substituteCounts.keys)
                      key: switch (lastExits[key]) {
                        final exit? =>
                          substitutionSalvoColorAt(exit.colorIndex),
                        null => substitutionStartColor,
                      },
                  },
                  namesOnly: true,
                  nameSuffixes: {
                    for (final MapEntry(:key, :value) in minutesOnField(
                      field: lineup.entriesFor(MatchCompositionZone.field),
                      events: bundle.events,
                      elapsed: bundle.session.elapsedAt(DateTime.now()),
                    ).entries)
                      key: "$value'",
                  },
                  nameColors: {
                    for (final id in nextOut.sure) id: nextOutSureColor,
                    for (final id in nextOut.toChoose) id: nextOutToChooseColor,
                  },
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
    );

    if (widget.fullScreen) {
      return _buildFullScreen(
        context,
        lineup: lineup,
        pitchArea: pitchArea,
        controller: controller,
        scorerCandidates: scorerCandidates,
        setupControlsDisabled: setupControlsDisabled,
      );
    }

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
        if (canEdit) ...[
          Row(
            key: const ValueKey('live-running-controls'),
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('live-formation-${lineup.formationCode}'),
                  initialValue: formationForCode(lineup.formationCode).code,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Dispositif',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 16,
                    ),
                  ),
                  items: [
                    for (final formation in footballFormations)
                      DropdownMenuItem(
                        value: formation.code,
                        child: Text(formation.code),
                      ),
                  ],
                  onChanged: setupControlsDisabled
                      ? null
                      : (value) {
                          if (value != null) {
                            _changeFormation(lineup, value, controller);
                          }
                        },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: OutlinedButton(
                    onPressed: setupControlsDisabled
                        ? null
                        : () => showMatchLiveAddPlayerSheet(
                              context,
                              ref,
                              matchId: matchId,
                            ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Ajouter un joueur'),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        _LiveHeaderBar(
          bundle: bundle,
          canEdit: canEdit,
          onPause: () => controller.setClockState('pause'),
          onResume: () => controller.setClockState('resume'),
          onResumeSecondHalf: () =>
              controller.setClockState('resume_second_half'),
          onHalftime: () => _confirmHalftime(context, controller),
          onRestart: () => _confirmRestart(context, controller),
          onEndMatch: () => _confirmEndMatch(context, controller),
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        pitchArea,
        // Remplacements en préparation : sous le terrain, pour qu'il ne
        // descende pas à chaque joueur sélectionné.
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
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Valide ou annule les remplacements en attente avant de '
              'changer de dispositif ou d’ajouter un joueur.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
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

  /// Vue pilote, posée dans la fiche du match.
  Widget _buildFullScreen(
    BuildContext context, {
    required MatchComposition lineup,
    required Widget pitchArea,
    required MatchLiveStateController controller,
    required List<MatchCompositionEntry> scorerCandidates,
    required bool setupControlsDisabled,
  }) {
    final session = bundle.session;
    final canGoHalftime =
        session.half == 1 && session.state != MatchLiveState.halftime;
    final goalsToAttribute = [
      for (final event in bundle.events)
        if (event.type == MatchLiveEventType.goalUs && event.needsScorer) event,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: _LiveHeaderBar(
            bundle: bundle,
            canEdit: canEdit,
            onlyClockAction: true,
            onPause: () => controller.setClockState('pause'),
            onResume: () => controller.setClockState('resume'),
            onResumeSecondHalf: () =>
                controller.setClockState('resume_second_half'),
            onHalftime: () => _confirmHalftime(context, controller),
            onRestart: () => _confirmRestart(context, controller),
            onEndMatch: () => _confirmEndMatch(context, controller),
            showClockAction: false,
            // Seconde ligne : commandes du match à gauche, consultation à
            // droite.
            bottom: Row(
              children: [
                if (canEdit) ...[
                  _MatchModeAction(
                    icon: Icons.sports_rounded,
                    label: 'Mi-temps',
                    onPressed: canGoHalftime
                        ? () => _confirmHalftime(context, controller)
                        : null,
                  ),
                  _MatchModeAction(
                    icon: Icons.flag_rounded,
                    label: 'Fin',
                    tooltip: 'Fin du match',
                    danger: true,
                    onPressed: () => _confirmEndMatch(context, controller),
                  ),
                  _MatchModeAction(
                    icon: Icons.restart_alt_rounded,
                    label: 'Reset',
                    tooltip: 'Recommencer le match',
                    onPressed: () => _confirmRestart(context, controller),
                  ),
                  switch (session.state) {
                    MatchLiveState.running => _MatchModeAction(
                        icon: Icons.pause_rounded,
                        label: 'Pause',
                        onPressed: () => controller.setClockState('pause'),
                      ),
                    MatchLiveState.paused => _MatchModeAction(
                        icon: Icons.play_arrow_rounded,
                        label: 'Reprendre',
                        onPressed: () => controller.setClockState('resume'),
                      ),
                    MatchLiveState.halftime => _MatchModeAction(
                        icon: Icons.play_arrow_rounded,
                        label: '2e mi-temps',
                        tooltip: 'Reprendre la 2e mi-temps',
                        onPressed: () =>
                            controller.setClockState('resume_second_half'),
                      ),
                    _ => const _MatchModeAction(
                        icon: Icons.pause_rounded,
                        label: 'Pause',
                        onPressed: null,
                      ),
                  },
                  Container(
                    width: 1,
                    height: 36,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    color: Theme.of(context).dividerColor,
                  ),
                ] else
                  const Spacer(flex: 4),
                _MatchModeAction(
                  icon: Icons.receipt_long_rounded,
                  label: 'Journal',
                  tooltip: 'Journal du match',
                  badgeCount: bundle.events.length,
                  onPressed: () =>
                      _openJournal(context, controller, scorerCandidates),
                ),
                if (canEdit)
                  _MatchModeAction(
                    icon: Icons.grid_view_rounded,
                    label: formationForCode(lineup.formationCode).code,
                    tooltip: 'Changer de dispositif',
                    onPressed: setupControlsDisabled
                        ? null
                        : () => _onMatchMenu(
                              context,
                              'formation',
                              lineup,
                              controller,
                            ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
          child: pitchArea,
        ),
        // Sous le terrain : buts à attribuer et changements en attente.
        if (canEdit && (_pending.isNotEmpty || goalsToAttribute.isNotEmpty))
          Material(
            color: Colors.transparent,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Buts d'AS Grinta sans buteur : un appui pour désigner
                    // le buteur puis le passeur.
                    for (final event in goalsToAttribute)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _GoalToAttributeBar(
                          event: event,
                          onChoose: () => _pickGoalScorer(
                            context,
                            controller,
                            event,
                            scorerCandidates,
                          ),
                        ),
                      ),
                    if (_pending.isNotEmpty)
                      _PendingSubstitutions(
                        pending: _pending,
                        nameOf: (participantId) =>
                            _nameOf(lineup, participantId),
                        busy: _saving,
                        onRemove: (pair) =>
                            setState(() => _pending.remove(pair)),
                        onClear: () => setState(_pending.clear),
                        onValidate: () => _validatePending(lineup, controller),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Pendant le match, seul un joueur du banc peut quitter la feuille : un
  /// joueur du terrain sort par un remplacement.
  Future<void> _removeBenchPlayer(
    MatchComposition lineup,
    MatchLiveStateController controller,
  ) async {
    final removed = await showMatchLiveRemovePlayerPicker(
      context,
      candidates: lineup.entriesFor(MatchCompositionZone.bench),
      note: 'Pendant le match, seuls les joueurs du banc peuvent être '
          'retirés. Un joueur du terrain sort par un remplacement.',
    );
    if (removed == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await controller.saveLiveLineup(
        entries: lineupWithoutPlayer(lineup, removed),
        expectedLineupRevision: bundle.session.lineupRevision,
      );
      if (!mounted) return;
      _showMessage(context, '${removed.displayName} retiré du match.');
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        context,
        'Impossible de retirer ce joueur. L’état Live a été resynchronisé.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onMatchMenu(
    BuildContext context,
    String value,
    MatchComposition lineup,
    MatchLiveStateController controller,
  ) async {
    switch (value) {
      case 'halftime':
        await _confirmHalftime(context, controller);
      case 'formation':
        final current = formationForCode(lineup.formationCode).code;
        final code = await showDialog<String>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
            title: const Text('Dispositif'),
            children: [
              for (final formation in footballFormations)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, formation.code),
                  child: Row(
                    children: [
                      Expanded(child: Text(formation.code)),
                      if (formation.code == current)
                        const Icon(Icons.check_rounded, size: 20),
                    ],
                  ),
                ),
            ],
          ),
        );
        if (code != null && mounted) {
          await _changeFormation(lineup, code, controller);
        }
      case 'add':
        await showMatchLiveAddPlayerSheet(context, ref, matchId: matchId);
      case 'restart':
        await _confirmRestart(context, controller);
      case 'end':
        await _confirmEndMatch(context, controller);
    }
  }

  /// Journal en volet par-dessus l'écran : il suit l'état du direct, pour
  /// qu'une suppression ou un buteur corrigé s'y voie tout de suite.
  Future<void> _openJournal(
    BuildContext context,
    MatchLiveStateController controller,
    List<MatchCompositionEntry> scorerCandidates,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .6,
        minChildSize: .3,
        maxChildSize: .92,
        builder: (_, scrollController) => Consumer(
          builder: (_, ref, __) {
            final events = ref
                    .watch(matchLiveStateProvider(matchId))
                    .valueOrNull
                    ?.events ??
                bundle.events;
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              child: _LiveJournal(
                events: events,
                expanded: true,
                canEdit: canEdit,
                onExpandedChanged: (_) {},
                onEditScorer: (event) => _pickGoalScorer(
                  context,
                  controller,
                  event,
                  scorerCandidates,
                ),
                onEditAssist: (event) => _pickGoalAssist(
                  context,
                  controller,
                  event,
                  scorerCandidates,
                ),
                onDelete: (event) =>
                    _confirmDeleteEvent(context, controller, event),
              ),
            );
          },
        ),
      ),
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
      // Proposé seulement si le but est déjà attribué : c'est le moyen de
      // revenir en arrière sur un buteur désigné par erreur.
      clearChoiceLabel:
          event.needsScorer ? null : 'Effacer · buteur à désigner plus tard',
    );
    if (choice == null) return;
    if (choice == kMatchLiveExtraChoiceId) {
      await controller.setEventScorer(event.id, isOpponentOwnGoal: true);
      return;
    }
    if (choice == kMatchLiveClearChoiceId) {
      // Sans buteur, la passe décisive n'a plus de sens : elle part avec lui.
      await controller.setEventScorer(event.id);
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
    // Feuille fermée sans répondre : on garde la passe décisive déjà connue
    // quand le buteur n'a pas changé. S'il a changé, l'ancienne passe ne veut
    // plus rien dire (elle pourrait même désigner le nouveau buteur).
    final assistParticipantId = assist.answered
        ? assist.participantId
        : (choice == event.scorerParticipantId
            ? event.assistParticipantId
            : null);
    await controller.setEventScorer(
      event.id,
      scorerParticipantId: choice,
      assistParticipantId: assistParticipantId,
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
    final title = event.type == MatchLiveEventType.substitution
        ? 'Retirer ce remplacement ?'
        : 'Retirer ce but ?';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mi-temps ?'),
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
        title: const Text('Fin du match ?'),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recommencer le match ?'),
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
