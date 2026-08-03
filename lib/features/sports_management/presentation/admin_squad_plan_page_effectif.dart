part of 'admin_squad_plan_page.dart';

extension _AdminSquadPlanEffectif on _AdminSquadPlanPageState {
  List<ConvocationPlayer> get _convokedPlayers {
    final players = (_convocations?.players ?? const <ConvocationPlayer>[])
        .where(
          (player) => _postMatch
              ? _actualPresent.contains(player.participantId)
              : (player.isAvailable || player.isGuest) &&
                  _desiredConvoked.contains(player.participantId),
        )
        .toList();
    players.sort(_convokedOrder);
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

  int _convokedOrder(ConvocationPlayer a, ConvocationPlayer b) {
    final ap = a.waitlistPosition;
    final bp = b.waitlistPosition;
    if (ap == null && bp == null) {
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    }
    if (ap == null) return 1;
    if (bp == null) return -1;
    final byPosition = bp.compareTo(ap);
    return byPosition != 0
        ? byPosition
        : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  }

  void _setConvoked(ConvocationPlayer player, bool value) {
    if (_busy || _locked || player.isGuest) return;
    _updateState(() {
      if (value) {
        _desiredConvoked.add(player.participantId);
      } else {
        _desiredConvoked.remove(player.participantId);
      }
    });
    unawaited(_persistEffectif());
  }

  void _scheduleEffectifSave() {
    _effectifSaveDebounce?.cancel();
    _effectifSaveDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) unawaited(_persistEffectif());
    });
  }

  int? _validatedSquadLimit({bool showError = true}) {
    final limit = int.tryParse(_limitController.text.trim());
    if (limit == null || limit < 1 || limit > 30) {
      if (showError) {
        _showMessage('Saisis une limite comprise entre 1 et 30.');
      }
      return null;
    }
    return limit;
  }

  Map<String, ConvocationStatus> _effectifDecisions(
    MatchConvocations convocations,
  ) {
    return {
      for (final player in convocations.players)
        if (!player.isGuest &&
            player.isAvailable &&
            player.seasonPlayerId.isNotEmpty)
          player.seasonPlayerId: _desiredConvoked.contains(player.participantId)
              ? ConvocationStatus.convoked
              : ConvocationStatus.notConvoked,
    };
  }

  Future<void> _persistEffectif() async {
    final convocations = _convocations;
    if (convocations == null || _locked) return;
    if (_busy) {
      _scheduleEffectifSave();
      return;
    }
    final limit = _validatedSquadLimit(showError: false);
    if (limit == null) return;

    _updateState(() => _busy = true);
    try {
      final updated =
          await ref.read(sportWaitlistRepositoryProvider).publishEffectif(
                matchId: convocations.matchId,
                squadSizeLimit: limit,
                decisions: _effectifDecisions(convocations),
                reason: 'Mise à jour immédiate de l’effectif depuis le match',
              );
      if (!mounted) return;
      _updateState(() {
        _convocations = updated;
        _desiredConvoked = {
          for (final player in updated.players)
            if ((player.isAvailable || player.isGuest) && player.isConvoked)
              player.participantId,
        };
      });
      ref.invalidate(matchAvailabilityBoardProvider(convocations.matchId));
    } catch (error) {
      if (mounted) {
        _showMessage(humanizeError(error));
        await _loadWorkspace(convocations.matchId);
      }
    } finally {
      if (mounted) _updateState(() => _busy = false);
    }
  }

  Future<void> _sendReminder({ConvocationPlayer? player}) async {
    final matchId = _selectedMatchId;
    final reminders = _reminders;
    if (matchId == null || reminders == null || !reminders.canRemind) return;

    final isCollective = player == null;
    if (isCollective && reminders.noResponseCount == 0) {
      _showMessage('Tous les joueurs ont déjà répondu.');
      return;
    }

    final confirmed = await _confirmAction(
      title: isCollective
          ? 'Relancer les sans réponse ?'
          : 'Relancer ${player.displayName} ?',
      actionLabel: 'Relancer',
      actionIcon: Icons.notifications_active_outlined,
      content: Text(
        isCollective
            ? '${reminders.noResponseCount} joueur'
                '${reminders.noResponseCount > 1 ? 's' : ''} sans réponse '
                'recevr${reminders.noResponseCount > 1 ? 'ont' : 'a'} une notification.'
            : 'Une notification de disponibilité sera envoyée. Un second envoi est bloqué pendant dix minutes.',
      ),
    );
    if (!confirmed || !mounted) return;

    _updateState(() => _busy = true);
    try {
      final repository = ref.read(sportWaitlistRepositoryProvider);
      final result = await repository.sendAvailabilityReminder(
        matchId: matchId,
        seasonPlayerId: player?.seasonPlayerId,
        reason: isCollective
            ? 'Relance collective depuis l’effectif'
            : 'Relance individuelle depuis l’effectif',
      );
      final updated = await repository.fetchReminderSummary(matchId);
      if (!mounted) return;
      _updateState(() => _reminders = updated);
      if (result.createdCount > 0) {
        _showMessage(
          '${result.createdCount} notification'
          '${result.createdCount > 1 ? 's' : ''} envoyée'
          '${result.createdCount > 1 ? 's' : ''}.',
        );
      } else if (result.skippedRecentCount > 0) {
        _showMessage('Relance déjà effectuée il y a moins de dix minutes.');
      } else {
        _showMessage('Aucun joueur à relancer.');
      }
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
    } finally {
      if (mounted) _updateState(() => _busy = false);
    }
  }

  void _showPlayerInfo(ConvocationPlayer player) {
    final status = player.availabilityStatus;
    final updatedAt = player.availabilityUpdatedAt;
    final (
      availabilityLabel,
      availabilityIcon,
      availabilityColor,
    ) = switch (status) {
      'available' => ('Disponible', Icons.check_circle_outline, Colors.green),
      'absent' => ('Absent', Icons.cancel_outlined, Colors.redAccent),
      _ => ('Sans réponse', Icons.schedule_outlined, Colors.orangeAccent),
    };
    final hasResponded = status == 'available' || status == 'absent';
    final availabilityDetail = player.isGuest
        ? 'Invité ajouté manuellement.'
        : hasResponded && updatedAt != null
            ? 'Indiquée le ${AppFormats.dateTime(updatedAt)}'
            : 'Aucune réponse enregistrée pour l’instant.';
    final waitlistDetail = player.waitlistPosition != null
        ? '${player.waitlistPosition}${player.waitlistPosition == 1 ? 'er' : 'e'} sur la liste d’attente'
        : 'Hors liste d’attente';
    final isConvoked = _desiredConvoked.contains(player.participantId);
    final convocationDetail = player.isGuest
        ? 'Invité sélectionné pour ce match'
        : isConvoked
            ? 'Convoqué pour ce match'
            : player.isAvailable
                ? 'Non convoqué pour ce match'
                : 'Aucune décision de convocation applicable';
    final canRelance = !player.isGuest &&
        status == 'no_response' &&
        !_locked &&
        (_reminders?.canRemind ?? false);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                player.displayName,
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              _PlayerInfoRow(
                icon: availabilityIcon,
                color: availabilityColor,
                title: availabilityLabel,
                detail: availabilityDetail,
              ),
              const SizedBox(height: 12),
              _PlayerInfoRow(
                icon: Icons.groups_rounded,
                color: isConvoked ? const Color(0xFF168A52) : Colors.blueGrey,
                title: 'Convocation',
                detail: convocationDetail,
              ),
              const SizedBox(height: 12),
              _PlayerInfoRow(
                icon: Icons.hourglass_top_rounded,
                color: const Color(0xFFE08A00),
                title: 'Liste d’attente',
                detail: waitlistDetail,
              ),
              if (!player.isGuest) ...[
                const SizedBox(height: 12),
                _PlayerInfoRow(
                  icon: Icons.repeat_rounded,
                  color: const Color(0xFFE08A00),
                  title: 'Nombre de tours en liste d’attente',
                  detail: '${player.currentSeasonWaitlistCount} fois',
                ),
              ],
              if (canRelance) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _sendReminder(player: player);
                    },
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Relancer ce joueur'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
    _updateState(() => _busy = true);
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
      if (mounted) _updateState(() => _busy = false);
    }
  }

  Future<void> _removeGuestFromMatch(ConvocationPlayer player) async {
    final matchId = _selectedMatchId;
    if (matchId == null || _busy || _locked || !player.isGuest) return;
    final confirmed = await _confirmAction(
      title: 'Retirer l’invité ?',
      actionLabel: 'Retirer',
      actionIcon: Icons.person_remove_outlined,
      content: Text('${player.displayName} sera retiré de ce match.'),
    );
    if (!confirmed || !mounted) return;
    _updateState(() => _busy = true);
    try {
      await ref.read(guestPlayersRepositoryProvider).removeGuest(
            matchId: matchId,
            participantId: player.participantId,
            reason: 'Retrait depuis Effectif',
          );
      await _loadWorkspace(matchId);
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
    } finally {
      if (mounted) _updateState(() => _busy = false);
    }
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
                  'Touche un joueur pour voir sa disponibilité et son rang. '
                  'Glisse-le pour changer de colonne. Chaque changement est '
                  'enregistré immédiatement.',
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
                  onChanged: (_) => _scheduleEffectifSave(),
                ),
                if (over) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${_convokedPlayers.length} joueurs pour une limite de $limit.',
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
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => context.push('/admin/waitlist'),
                  icon: const Icon(Icons.format_list_numbered_rounded),
                  label: const Text('Voir la liste d’attente'),
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
                title: 'Disponibles',
                color: const Color(0xFF168A52),
                icon: Icons.check_circle_outline,
                players: _convokedPlayers,
                acceptsDrops: true,
                onAccept: (player) => _setConvoked(player, true),
                onToggle: (player) => _setConvoked(player, false),
                onRemoveGuest: _removeGuestFromMatch,
                onShowInfo: _showPlayerInfo,
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
                onShowInfo: _showPlayerInfo,
                locked: _locked || _busy,
              ),
              _EffectifColumn(
                title: 'Absents',
                color: const Color(0xFFB33A3A),
                icon: Icons.cancel_outlined,
                players: _absentPlayers,
                onShowInfo: _showPlayerInfo,
                locked: true,
              ),
              _EffectifColumn(
                title: 'Sans réponse',
                color: const Color(0xFF6B7280),
                icon: Icons.schedule_outlined,
                players: _unansweredPlayers,
                locked: _busy || _locked,
                onShowInfo: _showPlayerInfo,
                onRelanceAll: (_reminders?.canRemind ?? false)
                    ? () => _sendReminder()
                    : null,
                onRelance: (_reminders?.canRemind ?? false)
                    ? (player) => _sendReminder(player: player)
                    : null,
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
        if (_locked)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('Effectif verrouillé au coup d’envoi.'),
          ),
      ],
    );
  }
}
