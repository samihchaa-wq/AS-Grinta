import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/inline_match_prediction_card.dart';
import 'package:as_grinta/features/sports_management/data/guest_players_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_availability_board_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/data/sport_waitlist_repository.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/formation_pitch_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _AdminStep { effectif, composition, prediction }

class AdminSquadPlanPage extends ConsumerStatefulWidget {
  const AdminSquadPlanPage({
    super.key,
    this.initialMatchId,
    this.initialStep,
    this.showPredictionStep = false,
  });

  final String? initialMatchId;
  final String? initialStep;
  final bool showPredictionStep;

  @override
  ConsumerState<AdminSquadPlanPage> createState() => _AdminSquadPlanPageState();
}

class _AdminSquadPlanPageState extends ConsumerState<AdminSquadPlanPage> {
  List<AdminSportMatch> _matches = const [];
  String? _selectedMatchId;
  MatchConvocations? _convocations;
  MatchComposition? _composition;
  Set<String> _desiredConvoked = {};
  late _AdminStep _step;
  late final TextEditingController _limitController;
  bool _loading = true;
  bool _busy = false;
  bool _effectifDirty = false;
  bool _compositionDirty = false;
  String? _error;

  _AdminStep _stepFrom(String? value) {
    if (widget.showPredictionStep && value == 'prediction') {
      return _AdminStep.prediction;
    }
    if (value == 'composition') return _AdminStep.composition;
    return _AdminStep.effectif;
  }

  @override
  void initState() {
    super.initState();
    _selectedMatchId = widget.initialMatchId;
    _step = _stepFrom(widget.initialStep);
    _limitController = TextEditingController(text: '14');
    Future.microtask(_loadMatches);
  }

  @override
  void didUpdateWidget(covariant AdminSquadPlanPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStep != widget.initialStep ||
        oldWidget.showPredictionStep != widget.showPredictionStep) {
      _step = _stepFrom(widget.initialStep);
    }
  }

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
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
        _loading = false;
        _error = humanizeError(error);
      });
    }
  }

  Future<void> _loadWorkspace(String matchId) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final waitlistRepository = ref.read(sportWaitlistRepositoryProvider);
      final compositionRepository = ref.read(
        matchCompositionRepositoryProvider,
      );
      final results = await Future.wait<Object?>([
        waitlistRepository.fetchMatchConvocations(matchId),
        compositionRepository.fetchAdminComposition(matchId),
      ]);
      final convocations = results[0] as MatchConvocations;
      final saved = results[1] as MatchComposition?;
      final goalkeeperIds =
          await compositionRepository.fetchGoalkeeperSeasonPlayerIds([
        for (final player in convocations.players)
          if (player.seasonPlayerId.isNotEmpty) player.seasonPlayerId,
      ]);
      final composition = _normalizeComposition(
        convocations,
        saved,
        goalkeeperIds,
      );
      if (!mounted || _selectedMatchId != matchId) return;
      setState(() {
        _convocations = convocations;
        _composition = composition;
        _desiredConvoked = {
          for (final player in convocations.players)
            if ((player.isAvailable || player.isGuest) && player.isConvoked)
              player.participantId,
        };
        _limitController.text = '${convocations.squadSizeLimit}';
        _effectifDirty = false;
        _compositionDirty = saved == null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = humanizeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  MatchComposition _normalizeComposition(
    MatchConvocations convocations,
    MatchComposition? saved,
    Set<String> goalkeeperIds,
  ) {
    final baseline = MatchComposition.initial(
      convocations: convocations,
      goalkeeperSeasonPlayerIds: goalkeeperIds,
    );
    if (saved == null) {
      return baseline.copyWith(
        entries: [
          for (final entry in baseline.entries)
            entry.canBeSelected
                ? entry.moveTo(MatchCompositionZone.bench)
                : entry.moveTo(MatchCompositionZone.notSelected),
        ],
      );
    }
    final savedById = {
      for (final entry in saved.entries) entry.participantId: entry,
    };
    return saved.copyWith(
      entries: [
        for (final base in baseline.entries)
          if (!base.canBeSelected)
            base.moveTo(MatchCompositionZone.notSelected)
          else if (savedById[base.participantId] case final previous?)
            MatchCompositionEntry(
              participantId: base.participantId,
              seasonPlayerId: base.seasonPlayerId,
              guestPlayerId: base.guestPlayerId,
              displayName: base.displayName,
              isGuest: base.isGuest,
              isGoalkeeper: base.isGoalkeeper,
              zone: previous.zone == MatchCompositionZone.field
                  ? MatchCompositionZone.field
                  : MatchCompositionZone.bench,
              x: previous.zone == MatchCompositionZone.field
                  ? previous.x
                  : null,
              y: previous.zone == MatchCompositionZone.field
                  ? previous.y
                  : null,
              slotLabel: previous.slotLabel,
              sortOrder: previous.sortOrder,
              availabilityStatus: base.availabilityStatus,
              convocationStatus: base.convocationStatus,
              selectionStatus: previous.zone == MatchCompositionZone.field
                  ? 'starter'
                  : 'substitute',
            )
          else
            base.moveTo(MatchCompositionZone.bench),
      ],
    );
  }

  bool get _locked {
    final kickoff = _convocations?.kickoffAt;
    return kickoff != null && !DateTime.now().isBefore(kickoff);
  }

  List<ConvocationPlayer> get _convokedPlayers {
    final players = (_convocations?.players ?? const <ConvocationPlayer>[])
        .where(
          (player) =>
              (player.isAvailable || player.isGuest) &&
              _desiredConvoked.contains(player.participantId),
        )
        .toList();
    players.sort(_playerOrder);
    return players;
  }

  List<ConvocationPlayer> get _waitlistedPlayers {
    final players = (_convocations?.players ?? const <ConvocationPlayer>[])
        .where(
          (player) =>
              player.isAvailable &&
              !player.isGuest &&
              !_desiredConvoked.contains(player.participantId),
        )
        .toList();
    players.sort(_playerOrder);
    return players;
  }

  List<ConvocationPlayer> get _absentPlayers {
    final players = (_convocations?.players ?? const <ConvocationPlayer>[])
        .where((player) => player.isAbsent)
        .toList();
    players.sort(_playerOrder);
    return players;
  }

  List<ConvocationPlayer> get _unansweredPlayers {
    final players = (_convocations?.players ?? const <ConvocationPlayer>[])
        .where((player) => player.availabilityStatus == 'no_response')
        .toList();
    players.sort(_playerOrder);
    return players;
  }

  int _playerOrder(ConvocationPlayer a, ConvocationPlayer b) {
    final byPosition = (a.waitlistPosition ?? 1 << 20).compareTo(
      b.waitlistPosition ?? 1 << 20,
    );
    return byPosition != 0
        ? byPosition
        : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  }

  void _setConvoked(ConvocationPlayer player, bool value) {
    if (_busy || _locked || player.isGuest) return;
    setState(() {
      if (value) {
        _desiredConvoked.add(player.participantId);
      } else {
        _desiredConvoked.remove(player.participantId);
      }
      _effectifDirty = true;
    });
  }

  Future<void> _saveEffectif() async {
    final convocations = _convocations;
    if (convocations == null || _busy || _locked) return;
    final limit = int.tryParse(_limitController.text.trim());
    if (limit == null || limit < 1 || limit > 30) {
      _showMessage('Saisis une limite comprise entre 1 et 30.');
      return;
    }
    setState(() => _busy = true);
    try {
      final repository = ref.read(sportWaitlistRepositoryProvider);
      await repository.saveEffectif(
        matchId: convocations.matchId,
        squadSizeLimit: limit,
        decisions: {
          for (final player in convocations.players)
            if (!player.isGuest &&
                player.isAvailable &&
                player.seasonPlayerId.isNotEmpty)
              player.seasonPlayerId:
                  _desiredConvoked.contains(player.participantId)
                      ? ConvocationStatus.convoked
                      : ConvocationStatus.notConvoked,
        },
        reason: 'Effectif enregistré depuis le match',
      );
      await _loadWorkspace(convocations.matchId);
      ref.invalidate(matchAvailabilityBoardProvider(convocations.matchId));
      if (!mounted) return;
      final count = _convokedPlayers.length;
      _showMessage(
        count > limit
            ? 'Effectif enregistré : $count convoqués pour une limite indicative de $limit.'
            : 'Effectif enregistré.',
      );
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  MatchCompositionEntry _entryWithStatus(
    MatchCompositionEntry entry,
    MatchCompositionZone zone, {
    double? x,
    double? y,
    int? sortOrder,
  }) {
    return MatchCompositionEntry(
      participantId: entry.participantId,
      seasonPlayerId: entry.seasonPlayerId,
      guestPlayerId: entry.guestPlayerId,
      displayName: entry.displayName,
      isGuest: entry.isGuest,
      isGoalkeeper: entry.isGoalkeeper,
      zone: zone,
      x: zone == MatchCompositionZone.field ? x : null,
      y: zone == MatchCompositionZone.field ? y : null,
      slotLabel: entry.slotLabel,
      sortOrder: sortOrder ?? entry.sortOrder,
      availabilityStatus: entry.availabilityStatus,
      convocationStatus: entry.convocationStatus,
      selectionStatus: switch (zone) {
        MatchCompositionZone.field => 'starter',
        MatchCompositionZone.bench => 'substitute',
        MatchCompositionZone.notSelected => 'not_selected',
        MatchCompositionZone.available => 'undecided',
      },
    );
  }

  void _dropOnSlot(MatchCompositionEntry moving, FootballFormationSlot slot) {
    final composition = _composition;
    if (composition == null || _busy || _locked) return;
    final currentAtSlot = composition.entries
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
    setState(() {
      _composition = composition.copyWith(
        formationCode: footballFormationByCode(composition.formationCode).code,
        hasUnpublishedChanges: true,
        entries: [
          for (final entry in composition.entries)
            if (entry.participantId == moving.participantId)
              _entryWithStatus(
                entry,
                MatchCompositionZone.field,
                x: slot.position.dx,
                y: slot.position.dy,
              )
            else if (currentAtSlot != null &&
                entry.participantId == currentAtSlot.participantId)
              oldPosition == null
                  ? _entryWithStatus(entry, MatchCompositionZone.bench)
                  : _entryWithStatus(
                      entry,
                      MatchCompositionZone.field,
                      x: oldPosition.dx,
                      y: oldPosition.dy,
                    )
            else
              entry,
        ],
      );
      _compositionDirty = true;
    });
  }

  void _moveToBench(MatchCompositionEntry moving) {
    final composition = _composition;
    if (composition == null || _busy || _locked) return;
    final benchCount =
        composition.entriesFor(MatchCompositionZone.bench).length;
    setState(() {
      _composition = composition.copyWith(
        hasUnpublishedChanges: true,
        entries: [
          for (final entry in composition.entries)
            if (entry.participantId == moving.participantId)
              _entryWithStatus(
                entry,
                MatchCompositionZone.bench,
                sortOrder: benchCount,
              )
            else
              entry,
        ],
      );
      _compositionDirty = true;
    });
  }

  void _reorderBench(int oldIndex, int newIndex) {
    final composition = _composition;
    if (composition == null || _busy || _locked) return;
    final bench = composition.entriesFor(MatchCompositionZone.bench);
    final moved = bench.removeAt(oldIndex);
    bench.insert(newIndex, moved);
    final order = {
      for (var index = 0; index < bench.length; index += 1)
        bench[index].participantId: index,
    };
    setState(() {
      _composition = composition.copyWith(
        hasUnpublishedChanges: true,
        entries: [
          for (final entry in composition.entries)
            if (order.containsKey(entry.participantId))
              _entryWithStatus(
                entry,
                MatchCompositionZone.bench,
                sortOrder: order[entry.participantId],
              )
            else
              entry,
        ],
      );
      _compositionDirty = true;
    });
  }

  void _applyFormation(String code) {
    final composition = _composition;
    if (composition == null || _busy || _locked) return;
    final formation = footballFormationByCode(code);
    final field = composition.entriesFor(MatchCompositionZone.field);
    field.sort((a, b) {
      if (a.isGoalkeeper != b.isGoalkeeper) return a.isGoalkeeper ? -1 : 1;
      final ay = a.y ?? .5;
      final by = b.y ?? .5;
      return by.compareTo(ay);
    });
    final assigned = <String, FootballFormationSlot>{};
    final free = [...formation.slots];
    for (final entry in field) {
      if (free.isEmpty) break;
      final current = Offset(entry.x ?? .5, entry.y ?? .5);
      free.sort(
        (a, b) => (current - a.position).distance.compareTo(
              (current - b.position).distance,
            ),
      );
      assigned[entry.participantId] = free.removeAt(0);
    }
    setState(() {
      _composition = composition.copyWith(
        formationCode: code,
        hasUnpublishedChanges: true,
        entries: [
          for (final entry in composition.entries)
            if (assigned[entry.participantId] case final slot?)
              _entryWithStatus(
                entry,
                MatchCompositionZone.field,
                x: slot.position.dx,
                y: slot.position.dy,
              )
            else
              entry,
        ],
      );
      _compositionDirty = true;
    });
  }

  MatchComposition _compositionReadyToSave() {
    final composition = _composition!;
    final currentConvoked = {
      for (final player in _convokedPlayers) player.participantId,
    };
    var benchOrder = 0;
    return composition.copyWith(
      entries: [
        for (final entry in composition.entries)
          if (!currentConvoked.contains(entry.participantId))
            _entryWithStatus(entry, MatchCompositionZone.notSelected)
          else if (entry.zone == MatchCompositionZone.field)
            entry
          else
            _entryWithStatus(
              entry,
              MatchCompositionZone.bench,
              sortOrder: benchOrder++,
            ),
      ],
    );
  }

  Future<MatchComposition?> _saveComposition({required bool publish}) async {
    if (_composition == null || _busy || _locked) return null;
    setState(() => _busy = true);
    try {
      final repository = ref.read(matchCompositionRepositoryProvider);
      final ready = _compositionReadyToSave();
      final saved = await repository.saveComposition(
        composition: ready,
        allowSquadSizeException: true,
        reason: publish
            ? 'Préparation de la publication'
            : 'Brouillon de composition',
      );
      if (publish) {
        await ref.read(sportWaitlistRepositoryProvider).publishMatch(
              matchId: ready.matchId,
              reason: 'Effectif confirmé avant publication de la composition',
            );
      }
      final result = publish
          ? await repository.publishComposition(
              matchId: ready.matchId,
              allowSquadSizeException: true,
              reason: 'Composition publiée depuis le match',
            )
          : saved;
      if (!mounted) return result;
      setState(() {
        _composition = result;
        _compositionDirty = false;
      });
      ref.invalidate(publishedMatchCompositionProvider(ready.matchId));
      _showMessage(publish ? 'Composition publiée.' : 'Brouillon enregistré.');
      return result;
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addGuest() async {
    final matchId = _selectedMatchId;
    if (matchId == null || _busy || _locked) return;
    final firstName = TextEditingController();
    final lastName = TextEditingController();
    var goalkeeper = false;
    final input = await showDialog<_GuestInput>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Ajouter un invité'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: firstName,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Prénom *'),
                ),
                TextField(
                  controller: lastName,
                  decoration: const InputDecoration(
                    labelText: 'Nom facultatif',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: goalkeeper,
                  title: const Text('Gardien'),
                  onChanged: (value) =>
                      setDialogState(() => goalkeeper = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final first = firstName.text.trim();
                if (first.isEmpty) return;
                Navigator.pop(
                  dialogContext,
                  _GuestInput(first, lastName.text.trim(), goalkeeper),
                );
              },
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
    firstName.dispose();
    lastName.dispose();
    if (input == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(guestPlayersRepositoryProvider).createAndAddGuest(
            matchId: matchId,
            firstName: input.firstName,
            lastName: input.lastName,
            isGoalkeeper: input.goalkeeper,
            reason: 'Ajout depuis Effectif',
          );
      await _loadWorkspace(matchId);
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
        title: const Text('Gestion du match'),
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
          SegmentedButton<_AdminStep>(
            segments: [
              const ButtonSegment(
                value: _AdminStep.effectif,
                icon: Icon(Icons.groups_2_outlined),
                label: Text('Effectif'),
              ),
              const ButtonSegment(
                value: _AdminStep.composition,
                icon: Icon(Icons.sports_soccer_outlined),
                label: Text('Composition'),
              ),
              if (widget.showPredictionStep)
                const ButtonSegment(
                  value: _AdminStep.prediction,
                  icon: Icon(Icons.sports_score_outlined),
                  label: Text('Ton pari'),
                ),
            ],
            selected: {_step},
            onSelectionChanged:
                _busy ? null : (value) => setState(() => _step = value.first),
          ),
          if (_busy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[const SizedBox(height: 12), Text(_error!)],
          const SizedBox(height: 16),
          if (_step == _AdminStep.prediction && _selectedMatchId != null)
            InlineMatchPredictionCard(matchId: _selectedMatchId!)
          else if (_convocations != null && _composition != null)
            _step == _AdminStep.effectif
                ? _buildEffectif()
                : _buildComposition(),
        ],
      ),
    );
  }

  Widget _buildEffectif() {
    final limit = int.tryParse(_limitController.text) ?? 14;
    final over = _convokedPlayers.length > limit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Effectif',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Les réponses évoluent en direct. Tes déplacements deviennent publics après enregistrement.',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _limitController,
                  enabled: !_busy && !_locked,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de joueurs souhaité',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() => _effectifDirty = true),
                ),
                if (over) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${_convokedPlayers.length} convoqués pour une limite indicative de $limit. L’enregistrement reste autorisé.',
                    style: const TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy || _locked ? null : _addGuest,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Ajouter un invité'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = [
              _EffectifColumn(
                title: 'Convoqués',
                color: const Color(0xFF168A52),
                icon: Icons.check_circle_outline,
                players: _convokedPlayers,
                acceptsDrops: true,
                onAccept: (player) => _setConvoked(player, true),
                onToggle: (player) => _setConvoked(player, false),
                locked: _locked || _busy,
              ),
              _EffectifColumn(
                title: 'Liste d’attente',
                color: const Color(0xFFE08A00),
                icon: Icons.hourglass_top_rounded,
                players: _waitlistedPlayers,
                acceptsDrops: true,
                onAccept: (player) => _setConvoked(player, false),
                onToggle: (player) => _setConvoked(player, true),
                locked: _locked || _busy,
              ),
              _EffectifColumn(
                title: 'Absents',
                color: const Color(0xFFB33A3A),
                icon: Icons.cancel_outlined,
                players: _absentPlayers,
                locked: true,
              ),
              _EffectifColumn(
                title: 'Sans réponse',
                color: const Color(0xFF6B7280),
                icon: Icons.schedule_outlined,
                players: _unansweredPlayers,
                locked: true,
              ),
            ];
            if (constraints.maxWidth >= 900) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < columns.length; index += 1) ...[
                    Expanded(child: columns[index]),
                    if (index < columns.length - 1) const SizedBox(width: 10),
                  ],
                ],
              );
            }
            return Column(
              children: [
                for (var index = 0; index < columns.length; index += 1) ...[
                  columns[index],
                  if (index < columns.length - 1) const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy || _locked ? null : _saveEffectif,
          icon: const Icon(Icons.save_outlined),
          label: Text(
            _effectifDirty ? 'Enregistrer l’effectif' : 'Effectif enregistré',
          ),
        ),
        if (_locked)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('Effectif verrouillé au coup d’envoi.'),
          ),
      ],
    );
  }

  Widget _buildComposition() {
    final composition = _composition!;
    final formation = footballFormationByCode(composition.formationCode);
    final field = composition.entriesFor(MatchCompositionZone.field);
    final bench = composition.entriesFor(MatchCompositionZone.bench)
      ..removeWhere((entry) => !_desiredConvoked.contains(entry.participantId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Composition',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Choisis un dispositif puis glisse les convoqués. Les emplacements vides restent visibles.',
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: formation.code,
                  decoration: const InputDecoration(
                    labelText: 'Dispositif',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final defenders in const [3, 4, 5]) ...[
                      DropdownMenuItem<String>(
                        enabled: false,
                        value: 'header-$defenders',
                        child: Text(
                          '$defenders défenseurs',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      for (final item in footballFormationsForDefenders(
                        defenders,
                      ))
                        DropdownMenuItem(
                          value: item.code,
                          child: Text(item.label),
                        ),
                    ],
                  ],
                  onChanged: _busy || _locked
                      ? null
                      : (value) {
                          if (value != null && !value.startsWith('header-')) {
                            _applyFormation(value);
                          }
                        },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: FormationPitchEditor(
            formation: formation,
            entries: field,
            editable: !_busy && !_locked,
            onDroppedOnSlot: _dropOnSlot,
            onRemoveFromField: _moveToBench,
          ),
        ),
        const SizedBox(height: 14),
        DragTarget<MatchCompositionEntry>(
          onWillAcceptWithDetails: (details) => !_busy && !_locked,
          onAcceptWithDetails: (details) => _moveToBench(details.data),
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
                    'Remplaçants (${bench.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (bench.isEmpty)
                    const Text('Aucun remplaçant.')
                  else
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      itemCount: bench.length,
                      onReorderItem: _reorderBench,
                      itemBuilder: (context, index) {
                        final entry = bench[index];
                        final tile = ListTile(
                          key: ValueKey(entry.participantId),
                          dense: true,
                          leading: entry.isGoalkeeper
                              ? const Icon(Icons.sports_handball)
                              : const Icon(Icons.person_outline),
                          title: Text(entry.displayName),
                          trailing: ReorderableDragStartListener(
                            index: index,
                            child: const Icon(Icons.drag_handle),
                          ),
                        );
                        if (_busy || _locked) return tile;
                        return LongPressDraggable<MatchCompositionEntry>(
                          key: ValueKey('drag-${entry.participantId}'),
                          data: entry,
                          feedback: Material(
                            child: SizedBox(width: 240, child: tile),
                          ),
                          childWhenDragging: Opacity(opacity: .3, child: tile),
                          child: tile,
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed:
              _busy || _locked ? null : () => _saveComposition(publish: false),
          icon: const Icon(Icons.save_outlined),
          label: Text(
            _compositionDirty
                ? 'Enregistrer le brouillon'
                : 'Brouillon enregistré',
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed:
              _busy || _locked ? null : () => _saveComposition(publish: true),
          icon: const Icon(Icons.campaign_outlined),
          label: Text(
            composition.isPublished ? 'Republier' : 'Publier la composition',
          ),
        ),
        if (_locked)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('Composition verrouillée au coup d’envoi.'),
          ),
      ],
    );
  }
}

class _EffectifColumn extends StatelessWidget {
  const _EffectifColumn({
    required this.title,
    required this.color,
    required this.icon,
    required this.players,
    required this.locked,
    this.acceptsDrops = false,
    this.onAccept,
    this.onToggle,
  });

  final String title;
  final Color color;
  final IconData icon;
  final List<ConvocationPlayer> players;
  final bool locked;
  final bool acceptsDrops;
  final ValueChanged<ConvocationPlayer>? onAccept;
  final ValueChanged<ConvocationPlayer>? onToggle;

  @override
  Widget build(BuildContext context) {
    return DragTarget<ConvocationPlayer>(
      onWillAcceptWithDetails: (details) =>
          acceptsDrops && !locked && !details.data.isGuest,
      onAcceptWithDetails: (details) => onAccept?.call(details.data),
      builder: (context, candidates, rejected) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: candidates.isNotEmpty
              ? color.withValues(alpha: .18)
              : color.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: candidates.isNotEmpty ? color : color.withValues(alpha: .35),
            width: candidates.isNotEmpty ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '$title (${players.length})',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            if (players.isEmpty)
              Text(
                'Aucun joueur.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final player in players)
                    _EffectifPlayerChip(
                      player: player,
                      color: color,
                      draggable: !locked && onToggle != null && !player.isGuest,
                      onTap: onToggle == null ? null : () => onToggle!(player),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _EffectifPlayerChip extends StatelessWidget {
  const _EffectifPlayerChip({
    required this.player,
    required this.color,
    required this.draggable,
    this.onTap,
  });

  final ConvocationPlayer player;
  final Color color;
  final bool draggable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = ActionChip(
      avatar: player.isGuest
          ? const Icon(Icons.person_add_alt_1_outlined, size: 16)
          : null,
      label: Text(
        player.firstName.trim().isEmpty
            ? player.displayName
            : player.firstName.trim(),
      ),
      onPressed: onTap,
      side: BorderSide(color: color.withValues(alpha: .55)),
      backgroundColor: color.withValues(alpha: .10),
    );
    if (!draggable) return chip;
    return LongPressDraggable<ConvocationPlayer>(
      data: player,
      feedback: Material(type: MaterialType.transparency, child: chip),
      childWhenDragging: Opacity(opacity: .3, child: chip),
      child: chip,
    );
  }
}

class _GuestInput {
  const _GuestInput(this.firstName, this.lastName, this.goalkeeper);
  final String firstName;
  final String lastName;
  final bool goalkeeper;
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month · $hour:$minute';
}
