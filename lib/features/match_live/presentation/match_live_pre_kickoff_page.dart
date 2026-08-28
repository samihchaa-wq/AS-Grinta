import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/match_live/domain/match_live_state_bundle.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/match_squad_editing.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/match_squad_editor.dart';
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
  bool _savingFormation = false;
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
        ],
        // Exactement le même bloc terrain/banc que le compte rendu
        // d'après-match : un seul éditeur d'effectif dans toute l'application.
        MatchSquadEditor(
          lineup: lineup,
          editable: widget.canEdit,
          header: widget.canEdit ? _buildHint(lineup) : null,
          onDroppedOnSlot: (moving, slot) => _dropOnSlot(lineup, moving, slot),
          onMoveToBench: (entry) => _moveToBench(lineup, entry),
          // Le dispositif se change aussi une fois le match lancé. L'avoir ici
          // évite d'attendre le coup d'envoi pour corriger un mauvais choix,
          // alors que l'écran Composition est déjà figé à ce stade.
          onFormationChanged: (code) => _changeFormation(lineup, code),
          formationBusy: _busy || _savingFormation,
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

  Widget _buildHint(MatchComposition lineup) {
    final empty = lineup.entriesFor(MatchCompositionZone.field).isEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                empty
                    ? 'Aucun titulaire n’est encore placé. Choisis un '
                        'dispositif, puis glisse les joueurs du banc sur '
                        'le terrain.'
                    : 'Vérifie la composition ci-dessous. Tu peux encore '
                        'la corriger : dispositif, terrain et banc.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeFormation(
    MatchComposition lineup,
    String formationCode,
  ) async {
    if (_busy || _savingFormation) return;
    final nextCode = formationForCode(formationCode).code;
    if (formationForCode(lineup.formationCode).code == nextCode) return;

    setState(() => _savingFormation = true);
    try {
      final changed = repositionForFormation(lineup, nextCode);
      await _controller.changeFormation(
        formationCode: nextCode,
        entries: [for (final entry in changed.entries) entry.toRpcJson()],
        expectedLineupRevision: widget.bundle.session.lineupRevision,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible de changer le dispositif. L’état Live a été '
            'resynchronisé.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingFormation = false);
    }
  }

  Future<void> _dropOnSlot(
    MatchComposition lineup,
    MatchCompositionEntry moving,
    FootballFormationSlot slot,
  ) async {
    final next = placeEntryOnSlot(lineup, moving, slot);
    await _controller.saveLiveLineup(
      entries: [for (final entry in next.entries) entry.toRpcJson()],
      expectedLineupRevision: widget.bundle.session.lineupRevision,
    );
  }

  Future<void> _moveToBench(
    MatchComposition lineup,
    MatchCompositionEntry moving,
  ) async {
    final next = moveEntryToBench(lineup, moving);
    await _controller.saveLiveLineup(
      entries: [for (final entry in next.entries) entry.toRpcJson()],
      expectedLineupRevision: widget.bundle.session.lineupRevision,
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
          'monde et cette composition devient celle que voient les joueurs.',
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
