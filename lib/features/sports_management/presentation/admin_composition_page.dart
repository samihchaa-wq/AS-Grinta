import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/sports_management/data/match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/data/sport_waitlist_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AdminCompositionPage extends ConsumerStatefulWidget {
  const AdminCompositionPage({super.key, this.initialMatchId});

  /// Quand fourni (ouverture depuis un match), la page se cale d'emblée sur ce
  /// match au lieu du premier match à venir.
  final String? initialMatchId;

  @override
  ConsumerState<AdminCompositionPage> createState() =>
      _AdminCompositionPageState();
}

class _AdminCompositionPageState extends ConsumerState<AdminCompositionPage> {
  List<AdminSportMatch> _matches = const [];
  String? _selectedMatchId;
  MatchConvocations? _convocations;
  MatchComposition? _composition;
  bool _loading = true;
  bool _busy = false;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedMatchId = widget.initialMatchId;
    Future.microtask(_loadMatches);
  }

  Future<void> _loadMatches() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final matches = await ref
          .read(sportWaitlistRepositoryProvider)
          .fetchUpcomingMatches();
      if (!mounted) return;
      final selected = _selectedMatchId != null &&
              matches.any((match) => match.id == _selectedMatchId)
          ? _selectedMatchId
          : (matches.isEmpty ? null : matches.first.id);
      setState(() {
        _matches = matches;
        _selectedMatchId = selected;
        _loading = false;
      });
      if (selected != null) await _loadWorkspace(selected);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = humanizeError(error);
        _loading = false;
      });
    }
  }

  Future<void> _loadWorkspace(String matchId) async {
    setState(() {
      _busy = true;
      _error = null;
      _convocations = null;
      _composition = null;
      _dirty = false;
    });
    try {
      final convocations = await ref
          .read(sportWaitlistRepositoryProvider)
          .fetchMatchConvocations(matchId);
      final repository = ref.read(matchCompositionRepositoryProvider);
      var composition = await repository.fetchAdminComposition(matchId);
      var isInitialDraft = false;
      if (composition == null) {
        final goalkeeperIds = await repository.fetchGoalkeeperSeasonPlayerIds([
          for (final player in convocations.players) player.seasonPlayerId,
        ]);
        composition = MatchComposition.initial(
          convocations: convocations,
          goalkeeperSeasonPlayerIds: goalkeeperIds,
        );
        isInitialDraft = true;
      }
      if (!mounted || _selectedMatchId != matchId) return;
      setState(() {
        _convocations = convocations;
        _composition = composition;
        _dirty = isInitialDraft;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = humanizeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _movePlayer(
    MatchCompositionEntry entry,
    MatchCompositionZone zone,
    Offset? normalizedPosition,
  ) {
    final composition = _composition;
    if (composition == null || _busy) return;
    if (!entry.canBeSelected) {
      _showMessage('Ce joueur doit d’abord être disponible et convoqué.');
      return;
    }
    if (zone == MatchCompositionZone.notSelected) {
      _showMessage('Modifie sa convocation depuis l’écran Convocations.');
      return;
    }
    if (zone == MatchCompositionZone.field &&
        entry.zone != MatchCompositionZone.field &&
        composition.fieldCount >= 11) {
      _showMessage('Le terrain est limité à 11 titulaires.');
      return;
    }

    final position = zone == MatchCompositionZone.field
        ? normalizedPosition ??
            (entry.zone == MatchCompositionZone.field &&
                    entry.x != null &&
                    entry.y != null
                ? Offset(entry.x!, entry.y!)
                : _nextFieldPosition(composition, entry))
        : null;
    final nextOrder = composition.entriesFor(zone).length;
    final updated = [
      for (final current in composition.entries)
        if (current.participantId == entry.participantId)
          current.moveTo(
            zone,
            x: position?.dx,
            y: position?.dy,
            sortOrder: nextOrder,
          )
        else
          current,
    ];
    setState(() {
      _composition = composition.copyWith(
        entries: updated,
        hasUnpublishedChanges: true,
      );
      _dirty = true;
    });
  }

  Offset _nextFieldPosition(
    MatchComposition composition,
    MatchCompositionEntry entry,
  ) {
    final positions =
        _formationPositions[composition.formationCode ?? '4-3-3'] ??
            _formationPositions['4-3-3']!;
    final occupied = composition.entriesFor(MatchCompositionZone.field);
    for (final position in positions) {
      final isFree = occupied.every((player) {
        final current = Offset(player.x ?? 0.5, player.y ?? 0.5);
        return (current - position).distance > 0.08;
      });
      if (isFree) return position;
    }
    final index = occupied.length;
    return Offset(0.18 + (index % 4) * 0.21, 0.18 + ((index ~/ 4) % 3) * 0.28);
  }

  void _applyFormation(String code) {
    final composition = _composition;
    if (composition == null || _busy) return;
    if (code == 'Libre') {
      setState(() {
        _composition = composition.copyWith(
          formationCode: code,
          hasUnpublishedChanges: true,
        );
        _dirty = true;
      });
      return;
    }

    final positions = _formationPositions[code]!;
    final fieldPlayers = composition.entriesFor(MatchCompositionZone.field)
      ..sort((a, b) {
        if (a.isGoalkeeper != b.isGoalkeeper) return a.isGoalkeeper ? -1 : 1;
        return a.sortOrder.compareTo(b.sortOrder);
      });
    final positionByParticipant = <String, Offset>{
      for (var index = 0;
          index < fieldPlayers.length && index < positions.length;
          index += 1)
        fieldPlayers[index].participantId: positions[index],
    };
    final updated = [
      for (final entry in composition.entries)
        if (positionByParticipant.containsKey(entry.participantId))
          entry.moveTo(
            MatchCompositionZone.field,
            x: positionByParticipant[entry.participantId]!.dx,
            y: positionByParticipant[entry.participantId]!.dy,
            sortOrder: entry.sortOrder,
          )
        else
          entry,
    ];
    setState(() {
      _composition = composition.copyWith(
        formationCode: code,
        entries: updated,
        hasUnpublishedChanges: true,
      );
      _dirty = true;
    });
  }

  void _autoPlace() {
    final composition = _composition;
    if (composition == null || _busy) return;
    final selectable = composition.entries.where((entry) => entry.canBeSelected)
      ..toList();
    final players = selectable.toList()
      ..sort((a, b) {
        if (a.isGoalkeeper != b.isGoalkeeper) return a.isGoalkeeper ? -1 : 1;
        return a.sortOrder.compareTo(b.sortOrder);
      });
    final positions =
        _formationPositions[composition.formationCode ?? '4-3-3'] ??
            _formationPositions['4-3-3']!;
    final updatedById = <String, MatchCompositionEntry>{};
    for (var index = 0; index < players.length; index += 1) {
      final player = players[index];
      if (index < 11) {
        final position = positions[index];
        updatedById[player.participantId] = player.moveTo(
          MatchCompositionZone.field,
          x: position.dx,
          y: position.dy,
          sortOrder: index,
        );
      } else {
        updatedById[player.participantId] = player.moveTo(
          MatchCompositionZone.bench,
          sortOrder: index - 11,
        );
      }
    }
    setState(() {
      _composition = composition.copyWith(
        entries: [
          for (final entry in composition.entries)
            updatedById[entry.participantId] ?? entry,
        ],
        hasUnpublishedChanges: true,
      );
      _dirty = true;
    });
  }

  Future<void> _showPlayerActions(MatchCompositionEntry entry) async {
    if (!entry.canBeSelected) {
      final openConvocations = await showModalBottomSheet<bool>(
            context: context,
            showDragHandle: true,
            builder: (sheetContext) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ce joueur n’est pas disponible et convoqué pour ce match. '
                      'Sa décision se modifie depuis Convocations.',
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        icon: const Icon(Icons.how_to_reg_outlined),
                        label: const Text('Ouvrir les convocations'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ) ??
          false;
      if (openConvocations && mounted) context.push('/admin/convocations');
      return;
    }

    final selected = await showModalBottomSheet<MatchCompositionZone>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  entry.displayName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.sports_soccer),
                title: const Text('Placer titulaire'),
                onTap: () =>
                    Navigator.pop(sheetContext, MatchCompositionZone.field),
              ),
              ListTile(
                leading: const Icon(Icons.event_seat_outlined),
                title: const Text('Mettre sur le banc'),
                onTap: () =>
                    Navigator.pop(sheetContext, MatchCompositionZone.bench),
              ),
              ListTile(
                leading: const Icon(Icons.hourglass_empty),
                title: const Text('Laisser à placer'),
                onTap: () =>
                    Navigator.pop(sheetContext, MatchCompositionZone.available),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) _movePlayer(entry, selected, null);
  }

  Future<_SquadExceptionDecision?> _resolveSquadException(
    MatchComposition composition,
  ) async {
    final limit = _convocations?.squadSizeLimit ?? 14;
    if (composition.selectedCount <= limit) {
      return const _SquadExceptionDecision(allow: false, reason: null);
    }
    final controller = TextEditingController();
    final decision = await showDialog<_SquadExceptionDecision>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dépasser la limite du match ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${composition.selectedCount} joueurs sont placés pour une limite '
              'de $limit. Cette exception sera auditée.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motif de l’exception',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.isEmpty) return;
              Navigator.pop(
                dialogContext,
                _SquadExceptionDecision(allow: true, reason: reason),
              );
            },
            child: const Text('Autoriser exceptionnellement'),
          ),
        ],
      ),
    );
    controller.dispose();
    return decision;
  }

  Future<MatchComposition?> _saveDraft({bool announce = true}) async {
    final composition = _composition;
    if (composition == null) return null;
    if (composition.fieldCount > 11) {
      _showMessage('Le terrain est limité à 11 titulaires.');
      return null;
    }
    final decision = await _resolveSquadException(composition);
    if (decision == null) return null;
    setState(() => _busy = true);
    try {
      final saved = await ref
          .read(matchCompositionRepositoryProvider)
          .saveComposition(
            composition: composition,
            allowSquadSizeException: decision.allow,
            reason: decision.reason ?? 'Brouillon enregistré depuis Flutter',
          );
      if (!mounted) return saved;
      setState(() {
        _composition = saved;
        _dirty = false;
      });
      if (announce) _showMessage('Brouillon enregistré.');
      return saved;
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    var composition = _composition;
    if (composition == null || _busy) return;
    if (composition.availableCount > 0) {
      _showMessage(
        'Place chaque joueur convoqué sur le terrain ou sur le banc.',
      );
      return;
    }
    if (_dirty || composition.version == 0) {
      composition = await _saveDraft(announce: false);
      if (composition == null || !mounted) return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              composition!.isPublished
                  ? 'Republier la composition ?'
                  : 'Publier la composition ?',
            ),
            content: Text(
              '${composition.fieldCount} titulaire${composition.fieldCount > 1 ? 's' : ''} '
              'et ${composition.benchCount} remplaçant${composition.benchCount > 1 ? 's' : ''}. '
              'Les joueurs verront immédiatement cette version.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.campaign_outlined),
                label: Text(composition.isPublished ? 'Republier' : 'Publier'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      final published =
          await ref.read(matchCompositionRepositoryProvider).publishComposition(
                matchId: composition.matchId,
                allowSquadSizeException: composition.squadSizeExceptionApproved,
                reason: composition.isPublished
                    ? 'Republication depuis Flutter'
                    : 'Première publication depuis Flutter',
              );
      if (!mounted) return;
      setState(() {
        _composition = published;
        _dirty = false;
      });
      ref.invalidate(publishedMatchCompositionProvider(composition.matchId));
      _showMessage(
        published.version == 1
            ? 'Composition publiée.'
            : 'Composition republiée · version ${published.version}.',
      );
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GrintaAppBar(
        title: const Text('Composition'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loading || _busy ? null : _loadMatches,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _matches.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(_error!),
          const SizedBox(height: 12),
          FilledButton(onPressed: _loadMatches, child: const Text('Réessayer')),
        ],
      );
    }
    if (_matches.isEmpty) {
      return const Center(child: Text('Aucun match à venir.'));
    }

    return RefreshIndicator(
      onRefresh: _loadMatches,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedMatchId,
            decoration: const InputDecoration(
              labelText: 'Match',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final match in _matches)
                DropdownMenuItem(
                  value: match.id,
                  child: Text(
                    '${match.opponentName} · ${_formatDate(match.kickoffAt)}',
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => _selectedMatchId = value);
                    _loadWorkspace(value);
                  },
          ),
          const SizedBox(height: 14),
          if (_busy && _composition == null)
            const Center(child: CircularProgressIndicator())
          else if (_error != null && _composition == null)
            Text(_error!)
          else if (_composition != null && _convocations != null)
            _buildWorkspace(_composition!, _convocations!),
        ],
      ),
    );
  }

  Widget _buildWorkspace(
    MatchComposition composition,
    MatchConvocations convocations,
  ) {
    final pitch = Column(
      children: [
        CompositionPitch(
          entries: composition.entriesFor(MatchCompositionZone.field),
          editable: !_busy,
          onMoved: _movePlayer,
          onPlayerTap: _showPlayerActions,
        ),
        const SizedBox(height: 8),
        Text(
          'Appui long pour déplacer · appui simple pour les actions',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
    final zones = Column(
      children: [
        CompositionDropZone(
          title: 'À placer',
          subtitle: 'Convoqués disponibles sans position définitive.',
          icon: Icons.hourglass_empty,
          entries: composition.entriesFor(MatchCompositionZone.available),
          targetZone: MatchCompositionZone.available,
          onMoved: _movePlayer,
          onPlayerTap: _showPlayerActions,
        ),
        const SizedBox(height: 12),
        CompositionDropZone(
          title: 'Banc',
          subtitle: 'Remplaçants convoqués.',
          icon: Icons.event_seat_outlined,
          entries: composition.entriesFor(MatchCompositionZone.bench),
          targetZone: MatchCompositionZone.bench,
          onMoved: _movePlayer,
          onPlayerTap: _showPlayerActions,
        ),
        const SizedBox(height: 12),
        CompositionDropZone(
          title: 'Non convoqués',
          subtitle: 'La décision se modifie dans Convocations.',
          icon: Icons.person_off_outlined,
          entries: composition.entriesFor(MatchCompositionZone.notSelected),
          targetZone: MatchCompositionZone.notSelected,
          onMoved: _movePlayer,
          onPlayerTap: _showPlayerActions,
          acceptDrops: false,
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CompositionSummaryCard(
          composition: composition,
          convocations: convocations,
          dirty: _dirty,
          busy: _busy,
          onFormationChanged: _applyFormation,
          onAutoPlace: _autoPlace,
          onOpenConvocations: () => context.push('/admin/convocations'),
        ),
        if (_busy) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(),
        ],
        if (composition.hasGoalkeeperWarning && composition.fieldCount > 0) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.warning_amber_rounded),
              title: const Text('Aucun gardien titulaire'),
              subtitle: const Text(
                'La publication reste possible, mais vérifie la composition.',
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 900) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: pitch),
                  const SizedBox(width: 18),
                  Expanded(flex: 2, child: zones),
                ],
              );
            }
            return Column(children: [pitch, const SizedBox(height: 16), zones]);
          },
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _saveDraft(),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    _dirty ? 'Enregistrer le brouillon' : 'Enregistré',
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _busy ? null : _publish,
                  icon: const Icon(Icons.campaign_outlined),
                  label: Text(
                    composition.isPublished
                        ? 'Republier la composition'
                        : 'Publier la composition',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CompositionSummaryCard extends StatelessWidget {
  const _CompositionSummaryCard({
    required this.composition,
    required this.convocations,
    required this.dirty,
    required this.busy,
    required this.onFormationChanged,
    required this.onAutoPlace,
    required this.onOpenConvocations,
  });

  final MatchComposition composition;
  final MatchConvocations convocations;
  final bool dirty;
  final bool busy;
  final ValueChanged<String> onFormationChanged;
  final VoidCallback onAutoPlace;
  final VoidCallback onOpenConvocations;

  @override
  Widget build(BuildContext context) {
    final overLimit = composition.selectedCount > convocations.squadSizeLimit;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${convocations.opponentName} · ${_formatDate(convocations.kickoffAt)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                Chip(
                  avatar: Icon(
                    dirty ? Icons.edit_outlined : Icons.cloud_done_outlined,
                    size: 18,
                  ),
                  label: Text(
                    dirty ? 'Non enregistré' : composition.publicationLabel,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('${composition.fieldCount}/11 titulaires')),
                Chip(label: Text('${composition.benchCount} sur le banc')),
                Chip(
                  label: Text(
                    '${composition.selectedCount}/${convocations.squadSizeLimit} sélectionnés',
                  ),
                  side: overLimit
                      ? BorderSide(color: Theme.of(context).colorScheme.error)
                      : null,
                ),
                if (composition.version > 0)
                  Chip(label: Text('Version ${composition.version}')),
              ],
            ),
            if (overLimit) ...[
              const SizedBox(height: 10),
              Text(
                'Le quota est dépassé. Une justification sera demandée à la sauvegarde.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final formation = DropdownButtonFormField<String>(
                  key: ValueKey(composition.formationCode),
                  initialValue:
                      _formationPositions.containsKey(composition.formationCode)
                          ? composition.formationCode
                          : 'Libre',
                  decoration: const InputDecoration(
                    labelText: 'Formation',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final code in _formationPositions.keys)
                      DropdownMenuItem(value: code, child: Text(code)),
                  ],
                  onChanged: busy
                      ? null
                      : (value) {
                          if (value != null) onFormationChanged(value);
                        },
                );
                final actions = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: busy ? null : onAutoPlace,
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: const Text('Répartir automatiquement'),
                    ),
                    TextButton.icon(
                      onPressed: busy ? null : onOpenConvocations,
                      icon: const Icon(Icons.how_to_reg_outlined),
                      label: const Text('Convocations'),
                    ),
                  ],
                );
                if (constraints.maxWidth < 620) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [formation, const SizedBox(height: 10), actions],
                  );
                }
                return Row(
                  children: [
                    SizedBox(width: 190, child: formation),
                    const SizedBox(width: 12),
                    Expanded(child: actions),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SquadExceptionDecision {
  const _SquadExceptionDecision({required this.allow, required this.reason});

  final bool allow;
  final String? reason;
}

const _formationPositions = <String, List<Offset>>{
  '4-3-3': [
    Offset(0.50, 0.90),
    Offset(0.14, 0.72),
    Offset(0.38, 0.73),
    Offset(0.62, 0.73),
    Offset(0.86, 0.72),
    Offset(0.24, 0.48),
    Offset(0.50, 0.52),
    Offset(0.76, 0.48),
    Offset(0.18, 0.20),
    Offset(0.50, 0.16),
    Offset(0.82, 0.20),
  ],
  '4-4-2': [
    Offset(0.50, 0.90),
    Offset(0.14, 0.72),
    Offset(0.38, 0.73),
    Offset(0.62, 0.73),
    Offset(0.86, 0.72),
    Offset(0.14, 0.44),
    Offset(0.38, 0.48),
    Offset(0.62, 0.48),
    Offset(0.86, 0.44),
    Offset(0.34, 0.18),
    Offset(0.66, 0.18),
  ],
  '3-5-2': [
    Offset(0.50, 0.90),
    Offset(0.22, 0.72),
    Offset(0.50, 0.75),
    Offset(0.78, 0.72),
    Offset(0.10, 0.43),
    Offset(0.30, 0.50),
    Offset(0.50, 0.45),
    Offset(0.70, 0.50),
    Offset(0.90, 0.43),
    Offset(0.34, 0.18),
    Offset(0.66, 0.18),
  ],
  'Libre': [
    Offset(0.50, 0.90),
    Offset(0.15, 0.72),
    Offset(0.38, 0.72),
    Offset(0.62, 0.72),
    Offset(0.85, 0.72),
    Offset(0.20, 0.45),
    Offset(0.50, 0.48),
    Offset(0.80, 0.45),
    Offset(0.20, 0.18),
    Offset(0.50, 0.15),
    Offset(0.80, 0.18),
  ],
};

String _formatDate(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month · $hour:$minute';
}
