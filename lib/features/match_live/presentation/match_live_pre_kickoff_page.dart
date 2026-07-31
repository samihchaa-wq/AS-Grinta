import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/match_live/domain/match_live_state_bundle.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/live_bench_tile.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/formation_pitch_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Avant le coup d'envoi suivi : reprend la composition publiée, permet de
/// la corriger en glisser-déposer, entre le temps de jeu, puis démarre.
class MatchLivePreKickoffPage extends ConsumerStatefulWidget {
  const MatchLivePreKickoffPage({
    super.key,
    required this.matchId,
    required this.bundle,
    required this.canEdit,
  });

  final String matchId;
  final MatchLiveStateBundle bundle;
  final bool canEdit;

  @override
  ConsumerState<MatchLivePreKickoffPage> createState() =>
      _MatchLivePreKickoffPageState();
}

class _MatchLivePreKickoffPageState
    extends ConsumerState<MatchLivePreKickoffPage> {
  late final TextEditingController _durationController = TextEditingController(
    text: '${widget.bundle.session.planPlannedDurationMinutes}',
  );
  bool _busy = false;
  late bool _opening = widget.canEdit && !widget.bundle.session.sessionExists;
  String? _openError;

  @override
  void initState() {
    super.initState();
    if (_opening) {
      // setState ne peut pas être appelé pendant la phase de build : on
      // reporte l'ouverture au premier post-frame, une fois le premier
      // rendu (avec le loader) déjà affiché.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openWorkspaceIfNeeded();
      });
    }
  }

  @override
  void dispose() {
    _durationController.dispose();
    super.dispose();
  }

  MatchLiveStateController get _controller =>
      ref.read(matchLiveStateProvider(widget.matchId).notifier);

  // La session live doit exister avant que le banc/terrain ne soit
  // modifiable : c'est cet appel qui copie la composition publiée dans
  // l'espace de travail éditable. Sans lui, la page resterait bloquée sur
  // "Composition indisponible" et le bouton "Démarrer le match" ne
  // s'afficherait jamais.
  Future<void> _openWorkspaceIfNeeded() async {
    setState(() {
      _opening = true;
      _openError = null;
    });
    try {
      await _controller.openWorkspace();
    } catch (error) {
      if (mounted) setState(() => _openError = humanizeError(error));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lineup = widget.bundle.lineup;
    if (lineup == null) {
      if (_openError != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_openError!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _openWorkspaceIfNeeded,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        );
      }
      if (_opening) {
        return const Center(
          child: GrintaLoader.page(
            message: 'Préparation du Tableau Blanc…',
            semanticLabel: 'Ouverture de l’espace de suivi en direct',
          ),
        );
      }
      return const Center(child: Text('Composition indisponible.'));
    }
    try {
      return _buildLoaded(context, lineup);
    } catch (error, stackTrace) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText(
            'Diagnostic Tableau Blanc (préparation) :\n$error\n\n$stackTrace',
            textAlign: TextAlign.left,
          ),
        ),
      );
    }
  }

  Widget _buildLoaded(BuildContext context, MatchComposition lineup) {
    final field = lineup.entriesFor(MatchCompositionZone.field);
    final bench = lineup.entriesFor(MatchCompositionZone.bench);

    // Cette liste est déjà imbriquée dans le scroll de la page qui l'affiche.
    // Sans shrinkWrap + NeverScrollableScrollPhysics, les deux listes se
    // disputent les gestes tactiles : scroll bloqué avant le bouton
    // « Démarrer le match » et glisser-déposer capturé par le mauvais niveau.
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        if (widget.canEdit) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Temps de jeu (minutes)',
                  prefixIcon: Icon(Icons.timer_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Vérifie la composition ci-dessous. Tu peux encore la '
                      'corriger en glissant les joueurs.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Center(
          child: FormationPitchEditor(
            slots: formationForCode(lineup.formationCode).slots,
            entries: field,
            editable: widget.canEdit,
            onDroppedOnSlot: (moving, slot) =>
                _dropOnSlot(lineup, moving, slot),
            onRemoveFromField: (entry) => _moveToBench(lineup, entry),
          ),
        ),
        const SizedBox(height: 14),
        DragTarget<MatchCompositionEntry>(
          onWillAcceptWithDetails: (details) => widget.canEdit,
          onAcceptWithDetails: (details) => _moveToBench(lineup, details.data),
          builder: (context, candidates, rejected) => Card(
            color: candidates.isNotEmpty
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Banc (${bench.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
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
                              entry: entry, draggable: widget.canEdit),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        if (widget.canEdit) ...[
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _confirmAndStart,
            icon: const Icon(Icons.play_circle_fill_rounded),
            label: const Text('Démarrer le match'),
          ),
        ],
      ],
    );
  }

  Future<void> _dropOnSlot(
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
    final oldPosition = moving.zone == MatchCompositionZone.field
        ? Offset(moving.x ?? .5, moving.y ?? .5)
        : null;
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
          oldPosition == null
              ? entry.moveTo(MatchCompositionZone.bench)
              : entry.moveTo(
                  MatchCompositionZone.field,
                  x: oldPosition.dx,
                  y: oldPosition.dy,
                )
        else
          entry,
    ];
    await _controller.saveLiveLineup(
      entries: [for (final entry in entries) entry.toRpcJson()],
    );
  }

  Future<void> _moveToBench(
    MatchComposition lineup,
    MatchCompositionEntry moving,
  ) async {
    final benchCount = lineup.entriesFor(MatchCompositionZone.bench).length;
    final entries = [
      for (final entry in lineup.entries)
        if (entry.participantId == moving.participantId)
          entry.moveTo(MatchCompositionZone.bench, sortOrder: benchCount)
        else
          entry,
    ];
    await _controller.saveLiveLineup(
      entries: [for (final entry in entries) entry.toRpcJson()],
    );
  }

  Future<void> _confirmAndStart() async {
    final minutes = int.tryParse(_durationController.text.trim());
    if (minutes == null || minutes < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entre un temps de jeu valide.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vérifiez que la composition est bonne'),
        content: const Text(
          'Une fois le match démarré, le chronomètre se lance pour tout le '
          'monde.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Corriger'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Démarrer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await _controller.openWorkspace(plannedDurationMinutes: minutes);
      await _controller.confirmStart();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
