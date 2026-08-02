import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/match_live/domain/match_live_event.dart';
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
  /// Les changements préparés par glisser-déposer, en attente de validation.
  final List<PendingSubstitution> _pending = [];
  bool _saving = false;

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

    // Les changements en attente sont affichés immédiatement sur le terrain
    // sans être envoyés au serveur. Le coach voit donc exactement la
    // composition qui sera enregistrée s'il valide. En annulant un changement,
    // on revient instantanément à la composition réellement enregistrée.
    final previewLineup = _previewLineup(lineup);
    final field = previewLineup.entriesFor(MatchCompositionZone.field);
    final bench = previewLineup.entriesFor(MatchCompositionZone.bench);
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
                  onPressed: () => _confirmHalftime(context, controller),
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
              // Repartir de zéro après un lancement par erreur ou une saisie
              // ratée : tout le direct est effacé et la préparation revient.
              OutlinedButton.icon(
                onPressed: () => _confirmRestart(context, controller),
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Recommencer'),
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
        const SizedBox(height: 20),
        // Banc à gauche, terrain à droite : le coach voit ses remplaçants
        // et le terrain d'un seul coup d'œil, sans faire défiler.
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
        if (canEdit && _pending.isNotEmpty) ...[
          const SizedBox(height: 14),
          _PendingSubstitutions(
            pending: _pending,
            nameOf: (participantId) => _nameOf(lineup, participantId),
            busy: _saving,
            onRemove: (pair) => setState(() => _pending.remove(pair)),
            onValidate: () => _validatePending(lineup, controller),
          ),
        ],
      ],
    );
  }

  /// Construit uniquement pour l'affichage la composition telle qu'elle sera
  /// après validation des remplacements. Rien n'est persisté ici.
  MatchComposition _previewLineup(MatchComposition lineup) {
    if (_pending.isEmpty) return lineup;

    final positions = {
      for (final entry in lineup.entriesFor(MatchCompositionZone.field))
        entry.participantId: Offset(entry.x ?? .5, entry.y ?? .5),
    };
    final incomingOf = {for (final pair in _pending) pair.playerIn: pair.playerOut};
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

  /// Prépare un changement au lieu de l'envoyer tout de suite : le coach
  /// peut en enchaîner plusieurs, puis tout valider d'un coup.
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
      _pending.add(
        (playerIn: playerIn.participantId, playerOut: playerOut.participantId),
      );
    });
  }

  String _nameOf(MatchComposition lineup, String participantId) {
    for (final entry in lineup.entries) {
      if (entry.participantId == participantId) return entry.displayName;
    }
    return '?';
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _explainHowToSubstitute(BuildContext context) {
    _showMessage(
      context,
      'Glisse ce joueur sur le remplaçant qui entre, à gauche du terrain.',
    );
  }

  /// Envoie toute la salve : les changements portent alors la même minute.
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
        substitutions: pairs,
      );
      if (mounted) setState(() => _pending.clear());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
      title: 'Qui a marqué à la ${event.minute}ᵉ minute ?',
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

  /// La mi-temps ne fige pas le chronomètre où il en est : elle le cale sur la
  /// moitié du temps de jeu saisi avant le coup d'envoi. Le coach doit savoir
  /// sur quelle minute il va atterrir avant de valider, surtout si le direct a
  /// pris du retard.
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

  /// « Recommencer » efface définitivement la saisie du direct. La confirmation
  /// énumère donc ce qui va disparaître, chiffres à l'appui, plutôt qu'un
  /// « Êtes-vous sûr ? » que personne ne lit.
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

    // Les changements préparés mais pas encore validés n'ont plus de sens.
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
      // On prépare le changement au lieu de l'envoyer : le coach peut en
      // enchaîner d'autres avant de tout valider. L'aperçu est immédiat.
      _stage(playerIn: moving, playerOut: currentAtSlot);
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
}

/// Le banc, en colonne verticale à gauche du terrain. Chaque remplaçant est
/// une cible : y déposer un titulaire prépare l'échange entre les deux.
/// Espace entre la colonne du banc et le terrain.
const double _benchGap = 10;

/// Ce que la colonne du banc ajoute autour d'une vignette (padding gauche et
/// droite du Card). Sert à répartir la largeur entre le banc et le terrain.
const double _benchColumnMargin = 14;

/// Répartit [availableWidth] entre la colonne du banc et le terrain.
///
/// La colonne du banc vaut une vignette plus ses marges et le terrain prend le
/// reste, mais la taille d'une vignette se déduit justement de la largeur du
/// terrain : on résout donc l'équation une fois pour les deux blocs, au lieu
/// de figer la taille du banc — ce qui faisait paraître les remplaçants plus
/// gros que les titulaires.
FormationMarkerMetrics benchAndPitchMetrics(double availableWidth) {
  final pitchWidth =
      (availableWidth - _benchGap - _benchColumnMargin) * 5.6 / 6.6;
  return FormationMarkerMetrics.forPitch(pitchWidth);
}

/// Largeur totale occupée par la colonne du banc pour ces [metrics].
double benchColumnWidth(FormationMarkerMetrics metrics) =>
    metrics.width + _benchColumnMargin;

class _BenchColumn extends StatelessWidget {
  const _BenchColumn({
    required this.bench,
    required this.bundle,
    required this.canEdit,
    required this.metrics,
    required this.onFieldPlayerDropped,
  });

  final List<MatchCompositionEntry> bench;
  final MatchLiveStateBundle bundle;
  final bool canEdit;
  final FormationMarkerMetrics metrics;

  /// (titulaire qui sort, remplaçant qui entre)
  final void Function(MatchCompositionEntry, MatchCompositionEntry)
      onFieldPlayerDropped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: metrics.width + _benchColumnMargin,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _benchColumnMargin / 2,
            vertical: 10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Banc (${bench.length})',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              if (bench.isEmpty)
                Text(
                  'Personne',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                )
              else
                for (final entry in bench)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DragTarget<MatchCompositionEntry>(
                      onWillAcceptWithDetails: (details) =>
                          canEdit &&
                          details.data.zone == MatchCompositionZone.field,
                      onAcceptWithDetails: (details) =>
                          onFieldPlayerDropped(details.data, entry),
                      builder: (context, candidates, rejected) => DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: candidates.isNotEmpty
                                ? theme.colorScheme.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: LiveBenchTile(
                          entry: entry,
                          draggable: canEdit,
                          metrics: metrics,
                          timesBenched: bundle.timesBenched(
                            entry.participantId,
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Les changements préparés, listés sous le terrain tant qu'ils ne sont pas
/// validés. Le coach peut en retirer un ou tout envoyer d'un coup.
class _PendingSubstitutions extends StatelessWidget {
  const _PendingSubstitutions({
    required this.pending,
    required this.nameOf,
    required this.busy,
    required this.onRemove,
    required this.onValidate,
  });

  final List<PendingSubstitution> pending;
  final String Function(String participantId) nameOf;
  final bool busy;
  final ValueChanged<PendingSubstitution> onRemove;
  final VoidCallback onValidate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              pending.length == 1
                  ? 'Aperçu du changement'
                  : 'Aperçu de ${pending.length} changements',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Le terrain affiche déjà le résultat. Valide pour enregistrer, '
              'ou annule pour remettre les joueurs à leur place précédente.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final pair in pending)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: LiveSubstitutionLine(
                        playerInName: nameOf(pair.playerIn),
                        playerOutName: nameOf(pair.playerOut),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Annuler ce changement',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.undo_rounded),
                      onPressed: busy ? null : () => onRemove(pair),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: busy ? null : onValidate,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: GrintaProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(
                pending.length == 1
                    ? 'Valider le changement'
                    : 'Valider les ${pending.length} changements',
              ),
            ),
          ],
        ),
      ),
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
    final fixture =
        ref.watch(upcomingMatchFixtureProvider(matchId)).valueOrNull;

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
      final label =
          event.isOpponentOwnGoal ? 'CSC adverse' : (event.scorerName ?? '?');
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