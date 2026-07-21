import 'dart:math' as math;

import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/sports_management/data/guest_players_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_squad_plan_repository.dart';
import 'package:as_grinta/features/sports_management/data/sport_waitlist_repository.dart';
import 'package:as_grinta/features/sports_management/domain/availability_reminder_models.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AdminSquadPlanPage extends ConsumerStatefulWidget {
  const AdminSquadPlanPage({super.key, this.initialMatchId});

  final String? initialMatchId;

  @override
  ConsumerState<AdminSquadPlanPage> createState() => _AdminSquadPlanPageState();
}

class _AdminSquadPlanPageState extends ConsumerState<AdminSquadPlanPage> {
  List<AdminSportMatch> _matches = const [];
  String? _selectedMatchId;
  MatchConvocations? _convocations;
  MatchComposition? _composition;
  AvailabilityReminderSummary? _reminders;
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
        _loading = false;
        _error = humanizeError(error);
      });
    }
  }

  Future<void> _loadWorkspace(String matchId) async {
    setState(() {
      _busy = true;
      _error = null;
      _convocations = null;
      _composition = null;
      _reminders = null;
      _dirty = false;
    });
    try {
      final waitlistRepository = ref.read(sportWaitlistRepositoryProvider);
      final compositionRepository = ref.read(
        matchCompositionRepositoryProvider,
      );
      final results = await Future.wait<Object?>([
        waitlistRepository.fetchMatchConvocations(matchId),
        waitlistRepository.fetchReminderSummary(matchId),
        compositionRepository.fetchAdminComposition(matchId),
      ]);
      final convocations = results[0] as MatchConvocations;
      final reminders = results[1] as AvailabilityReminderSummary;
      final saved = results[2] as MatchComposition?;
      final goalkeeperIds =
          await compositionRepository.fetchGoalkeeperSeasonPlayerIds([
        for (final player in convocations.players)
          if (player.seasonPlayerId.isNotEmpty) player.seasonPlayerId,
      ]);
      final baseline = MatchComposition.initial(
        convocations: convocations,
        goalkeeperSeasonPlayerIds: goalkeeperIds,
      );
      final normalized = _normalizeComposition(saved, baseline);
      if (!mounted || _selectedMatchId != matchId) return;
      setState(() {
        _convocations = convocations;
        _reminders = reminders;
        _composition = normalized;
        _dirty = saved == null || _differs(saved, normalized);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = humanizeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  MatchComposition _normalizeComposition(
    MatchComposition? saved,
    MatchComposition baseline,
  ) {
    if (saved == null) return baseline;
    final savedByParticipant = {
      for (final entry in saved.entries) entry.participantId: entry,
    };
    final entries = <MatchCompositionEntry>[];
    for (final base in baseline.entries) {
      final current = savedByParticipant[base.participantId];
      if (current == null) {
        entries.add(base);
      } else if (!_canPlace(current) &&
          current.zone != MatchCompositionZone.notSelected) {
        entries.add(base);
      } else {
        entries.add(current);
      }
    }
    return saved.copyWith(entries: entries);
  }

  bool _differs(MatchComposition left, MatchComposition right) {
    if (left.entries.length != right.entries.length) return true;
    final rightById = {
      for (final entry in right.entries) entry.participantId: entry,
    };
    for (final entry in left.entries) {
      final other = rightById[entry.participantId];
      if (other == null ||
          entry.zone != other.zone ||
          entry.x != other.x ||
          entry.y != other.y ||
          entry.sortOrder != other.sortOrder) {
        return true;
      }
    }
    return false;
  }

  bool _canPlace(MatchCompositionEntry entry) {
    return entry.isGuest || entry.availabilityStatus == 'available';
  }

  ConvocationPlayer? _playerFor(String participantId) {
    final players = _convocations?.players ?? const [];
    for (final player in players) {
      if (player.participantId == participantId) return player;
    }
    return null;
  }

  bool _isWaitlistConcerned(ConvocationPlayer player) {
    final convocations = _convocations;
    if (convocations == null || player.isGuest || !player.isAvailable) {
      return false;
    }
    final permanentPresent = convocations.players
        .where((item) => !item.isGuest && item.isAvailable)
        .length;
    final exclusions =
        math.max(0, permanentPresent - convocations.squadSizeLimit);
    final position = player.waitlistPosition;
    return exclusions > 0 && position != null && position <= exclusions;
  }

  void _movePlayer(
    MatchCompositionEntry entry,
    MatchCompositionZone zone,
    Offset? normalizedPosition,
  ) {
    final composition = _composition;
    if (composition == null || _busy) return;
    if (zone != MatchCompositionZone.notSelected && !_canPlace(entry)) {
      _showMessage('Ce joueur est absent ou n’a pas encore répondu.');
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
                : _nextFieldPosition(composition))
        : null;
    final nextOrder = composition.entriesFor(zone).length;
    setState(() {
      _composition = composition.copyWith(
        entries: [
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
        ],
        hasUnpublishedChanges: true,
      );
      _dirty = true;
    });
  }

  Offset _nextFieldPosition(MatchComposition composition) {
    final positions =
        _formationPositions[composition.formationCode ?? '4-3-3'] ??
            _formationPositions['4-3-3']!;
    final occupied = composition.entriesFor(MatchCompositionZone.field);
    for (final position in positions) {
      final free = occupied.every((player) {
        final current = Offset(player.x ?? 0.5, player.y ?? 0.5);
        return (current - position).distance > 0.08;
      });
      if (free) return position;
    }
    final index = occupied.length;
    return Offset(
      0.18 + (index % 4) * 0.21,
      0.18 + ((index ~/ 4) % 3) * 0.28,
    );
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
    final byParticipant = <String, Offset>{};
    for (var index = 0;
        index < fieldPlayers.length && index < positions.length;
        index += 1) {
      byParticipant[fieldPlayers[index].participantId] = positions[index];
    }
    setState(() {
      _composition = composition.copyWith(
        formationCode: code,
        entries: [
          for (final entry in composition.entries)
            if (byParticipant.containsKey(entry.participantId))
              entry.moveTo(
                MatchCompositionZone.field,
                x: byParticipant[entry.participantId]!.dx,
                y: byParticipant[entry.participantId]!.dy,
                sortOrder: entry.sortOrder,
              )
            else
              entry,
        ],
        hasUnpublishedChanges: true,
      );
      _dirty = true;
    });
  }

  Future<void> _showPlayerActions(MatchCompositionEntry entry) async {
    if (!_canPlace(entry)) {
      final player = _playerFor(entry.participantId);
      _showMessage(
        player?.isAbsent == true
            ? '${entry.displayName} est absent.'
            : '${entry.displayName} n’a pas encore répondu.',
      );
      return;
    }
    final action = await showModalBottomSheet<_PlayerAction>(
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
                onTap: () => Navigator.pop(sheetContext, _PlayerAction.field),
              ),
              ListTile(
                leading: const Icon(Icons.event_seat_outlined),
                title: const Text('Mettre sur le banc'),
                onTap: () => Navigator.pop(sheetContext, _PlayerAction.bench),
              ),
              ListTile(
                leading: const Icon(Icons.hourglass_empty),
                title: const Text('Laisser à placer'),
                onTap: () =>
                    Navigator.pop(sheetContext, _PlayerAction.available),
              ),
              ListTile(
                leading: const Icon(Icons.person_off_outlined),
                title: const Text('Laisser hors groupe'),
                onTap: () =>
                    Navigator.pop(sheetContext, _PlayerAction.notSelected),
              ),
              if (entry.isGuest)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Retirer cet invité du match'),
                  onTap: () =>
                      Navigator.pop(sheetContext, _PlayerAction.remove),
                ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _PlayerAction.field:
        _movePlayer(entry, MatchCompositionZone.field, null);
      case _PlayerAction.bench:
        _movePlayer(entry, MatchCompositionZone.bench, null);
      case _PlayerAction.available:
        _movePlayer(entry, MatchCompositionZone.available, null);
      case _PlayerAction.notSelected:
        _movePlayer(entry, MatchCompositionZone.notSelected, null);
      case _PlayerAction.remove:
        await _removeGuest(entry);
    }
  }

  Future<void> _sendReminder() async {
    final convocations = _convocations;
    final reminders = _reminders;
    if (convocations == null ||
        reminders == null ||
        !reminders.canRemind ||
        reminders.noResponseCount == 0 ||
        _busy) {
      return;
    }
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Relancer les sans réponse ?'),
            content: Text(
              '${reminders.noResponseCount} joueur${reminders.noResponseCount > 1 ? 's' : ''} recevra une notification.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Relancer'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      final repository = ref.read(sportWaitlistRepositoryProvider);
      final result = await repository.sendAvailabilityReminder(
        matchId: convocations.matchId,
        reason: 'Relance depuis Sélection & composition',
      );
      final updated = await repository.fetchReminderSummary(
        convocations.matchId,
      );
      if (!mounted) return;
      setState(() => _reminders = updated);
      _showMessage(
        result.createdCount > 0
            ? '${result.createdCount} notification${result.createdCount > 1 ? 's' : ''} envoyée${result.createdCount > 1 ? 's' : ''}.'
            : 'Aucune nouvelle notification envoyée.',
      );
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addGuest() async {
    final matchId = _selectedMatchId;
    if (matchId == null || _busy) return;
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
                  maxLength: 80,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Prénom *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lastName,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nom facultatif',
                    border: OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: goalkeeper,
                  title: const Text('Gardien'),
                  onChanged: (value) {
                    setDialogState(() => goalkeeper = value);
                  },
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
                  _GuestInput(
                    firstName: first,
                    lastName: lastName.text.trim(),
                    goalkeeper: goalkeeper,
                  ),
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
            reason: 'Ajout depuis Sélection & composition',
          );
      await _loadWorkspace(matchId);
      if (mounted) _showMessage('${input.firstName} ajouté au match.');
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeGuest(MatchCompositionEntry entry) async {
    final matchId = _selectedMatchId;
    if (matchId == null || _busy) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Retirer cet invité ?'),
            content: Text('${entry.displayName} sera retiré de ce match.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Retirer'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await ref.read(guestPlayersRepositoryProvider).removeGuest(
            matchId: matchId,
            participantId: entry.participantId,
            reason: 'Retrait depuis Sélection & composition',
          );
      await _loadWorkspace(matchId);
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _validatePlan({required bool publishing}) {
    final composition = _composition;
    final convocations = _convocations;
    if (composition == null || convocations == null) return false;
    if (composition.fieldCount > 11) {
      _showMessage('Le terrain est limité à 11 titulaires.');
      return false;
    }
    if (composition.selectedCount > convocations.squadSizeLimit) {
      _showMessage(
        'Retire ${composition.selectedCount - convocations.squadSizeLimit} joueur${composition.selectedCount - convocations.squadSizeLimit > 1 ? 's' : ''} du terrain ou du banc.',
      );
      return false;
    }
    if (publishing && composition.availableCount > 0) {
      _showMessage(
          'Place chaque joueur sélectionné sur le terrain ou le banc.');
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    final composition = _composition;
    if (composition == null || _busy || !_validatePlan(publishing: false)) {
      return;
    }
    setState(() => _busy = true);
    try {
      final saved = await ref.read(matchSquadPlanRepositoryProvider).savePlan(
            composition: composition,
            reason: 'Brouillon depuis Sélection & composition',
          );
      final convocations = await ref
          .read(sportWaitlistRepositoryProvider)
          .fetchMatchConvocations(composition.matchId);
      if (!mounted) return;
      setState(() {
        _composition = saved;
        _convocations = convocations;
        _dirty = false;
      });
      _showMessage('Sélection et composition enregistrées.');
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    final composition = _composition;
    if (composition == null || _busy || !_validatePlan(publishing: true)) {
      return;
    }
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(composition.isPublished
                ? 'Republier la sélection ?'
                : 'Publier la sélection ?'),
            content: Text(
              '${composition.fieldCount} titulaire${composition.fieldCount > 1 ? 's' : ''} et '
              '${composition.benchCount} remplaçant${composition.benchCount > 1 ? 's' : ''}. '
              'Les joueurs verront immédiatement la composition.',
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
          await ref.read(matchSquadPlanRepositoryProvider).publishPlan(
                composition: composition,
                reason: composition.isPublished
                    ? 'Republication depuis Sélection & composition'
                    : 'Première publication depuis Sélection & composition',
              );
      final waitlistRepository = ref.read(sportWaitlistRepositoryProvider);
      final convocations = await waitlistRepository.fetchMatchConvocations(
        composition.matchId,
      );
      final reminders = await waitlistRepository.fetchReminderSummary(
        composition.matchId,
      );
      if (!mounted) return;
      setState(() {
        _composition = published;
        _convocations = convocations;
        _reminders = reminders;
        _dirty = false;
      });
      ref.invalidate(publishedMatchCompositionProvider(composition.matchId));
      _showMessage('Sélection et composition publiées.');
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GrintaAppBar(
        title: const Text('Sélection & composition'),
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
          title: 'Présents à placer',
          subtitle: 'Joueurs sélectionnés sans position définitive.',
          icon: Icons.hourglass_empty,
          entries: composition.entriesFor(MatchCompositionZone.available),
          targetZone: MatchCompositionZone.available,
          onMoved: _movePlayer,
          onPlayerTap: _showPlayerActions,
        ),
        const SizedBox(height: 12),
        CompositionDropZone(
          title: 'Banc',
          subtitle: 'Remplaçants sélectionnés.',
          icon: Icons.event_seat_outlined,
          entries: composition.entriesFor(MatchCompositionZone.bench),
          targetZone: MatchCompositionZone.bench,
          onMoved: _movePlayer,
          onPlayerTap: _showPlayerActions,
        ),
        const SizedBox(height: 12),
        CompositionDropZone(
          title: 'Hors groupe',
          subtitle: 'Présents non sélectionnés, absents et sans réponse.',
          icon: Icons.person_off_outlined,
          entries: composition.entriesFor(MatchCompositionZone.notSelected),
          targetZone: MatchCompositionZone.notSelected,
          onMoved: _movePlayer,
          onPlayerTap: _showPlayerActions,
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PlanSummaryCard(
          composition: composition,
          convocations: convocations,
          reminders: _reminders,
          dirty: _dirty,
          busy: _busy,
          onReminder: _sendReminder,
          onGuest: _addGuest,
          onFormationChanged: _applyFormation,
        ),
        if (_busy) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 14),
        _AvailabilityBoard(
          convocations: convocations,
          isWaitlistConcerned: _isWaitlistConcerned,
        ),
        if (composition.hasGoalkeeperWarning && composition.fieldCount > 0) ...[
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.warning_amber_rounded),
              title: Text('Aucun gardien titulaire'),
              subtitle: Text('Vérifie la composition avant publication.'),
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
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label:
                      Text(_dirty ? 'Enregistrer le brouillon' : 'Enregistré'),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _busy ? null : _publish,
                  icon: const Icon(Icons.campaign_outlined),
                  label: Text(
                    composition.isPublished
                        ? 'Republier la sélection'
                        : 'Publier la sélection',
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

class _PlanSummaryCard extends StatelessWidget {
  const _PlanSummaryCard({
    required this.composition,
    required this.convocations,
    required this.reminders,
    required this.dirty,
    required this.busy,
    required this.onReminder,
    required this.onGuest,
    required this.onFormationChanged,
  });

  final MatchComposition composition;
  final MatchConvocations convocations;
  final AvailabilityReminderSummary? reminders;
  final bool dirty;
  final bool busy;
  final VoidCallback onReminder;
  final VoidCallback onGuest;
  final ValueChanged<String> onFormationChanged;

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
            if (composition.version > 0) ...[
              const SizedBox(height: 12),
              Chip(label: Text('Version ${composition.version}')),
            ],
            if (overLimit) ...[
              const SizedBox(height: 10),
              Text(
                'La limite est dépassée : laisse des joueurs hors groupe.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: ValueKey(composition.formationCode),
              initialValue: _formationPositions.containsKey(
                composition.formationCode,
              )
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
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: busy ||
                          reminders?.canRemind != true ||
                          reminders!.noResponseCount == 0
                      ? null
                      : onReminder,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Relancer les sans réponse'),
                ),
                FilledButton.tonalIcon(
                  onPressed: busy ? null : onGuest,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Ajouter un invité'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AvailabilityBoard extends StatelessWidget {
  const _AvailabilityBoard({
    required this.convocations,
    required this.isWaitlistConcerned,
  });

  final MatchConvocations convocations;
  final bool Function(ConvocationPlayer) isWaitlistConcerned;

  @override
  Widget build(BuildContext context) {
    final present = convocations.players
        .where((player) => player.isGuest || player.isAvailable)
        .toList();
    final absent =
        convocations.players.where((player) => player.isAbsent).toList();
    final unanswered = convocations.players
        .where((player) => player.availabilityStatus == 'no_response')
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Réponses des joueurs',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 12),
            _AvailabilityGroup(
              title: 'Présents',
              icon: Icons.check_circle_outline,
              color: const Color(0xFF168A52),
              players: present,
              isWaitlistConcerned: isWaitlistConcerned,
            ),
            const SizedBox(height: 12),
            _AvailabilityGroup(
              title: 'Absents',
              icon: Icons.cancel_outlined,
              color: const Color(0xFFB33A3A),
              players: absent,
              isWaitlistConcerned: isWaitlistConcerned,
            ),
            const SizedBox(height: 12),
            _AvailabilityGroup(
              title: 'Sans réponse',
              icon: Icons.schedule_outlined,
              color: const Color(0xFF6B7280),
              players: unanswered,
              isWaitlistConcerned: isWaitlistConcerned,
            ),
            if (present.any(isWaitlistConcerned)) ...[
              const SizedBox(height: 12),
              const Row(
                children: [
                  Icon(Icons.circle, size: 12, color: Color(0xFFF59E0B)),
                  SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Orange : joueurs concernés par la rotation de la liste d’attente.',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AvailabilityGroup extends StatelessWidget {
  const _AvailabilityGroup({
    required this.title,
    required this.icon,
    required this.color,
    required this.players,
    required this.isWaitlistConcerned,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<ConvocationPlayer> players;
  final bool Function(ConvocationPlayer) isWaitlistConcerned;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 7),
            Text(
              '$title (${players.length})',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (players.isEmpty)
          Text('Aucun joueur.', style: Theme.of(context).textTheme.bodySmall)
        else
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final player in players)
                Chip(
                  avatar: player.isGuest
                      ? const Icon(Icons.person_add_alt_1_outlined, size: 17)
                      : null,
                  label: Text(
                    player.firstName.trim().isEmpty
                        ? player.displayName
                        : player.firstName.trim(),
                  ),
                  backgroundColor: isWaitlistConcerned(player)
                      ? const Color(0xFFF59E0B).withValues(alpha: 0.20)
                      : color.withValues(alpha: 0.10),
                  side: BorderSide(
                    color: isWaitlistConcerned(player)
                        ? const Color(0xFFF59E0B)
                        : color.withValues(alpha: 0.45),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _GuestInput {
  const _GuestInput({
    required this.firstName,
    required this.lastName,
    required this.goalkeeper,
  });

  final String firstName;
  final String lastName;
  final bool goalkeeper;
}

enum _PlayerAction { field, bench, available, notSelected, remove }

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
