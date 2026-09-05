part of 'admin_squad_plan_page.dart';

const _effectifConvokedColor = AppTheme.availabilityIn;
const _effectifWaitlistColor = AppTheme.availabilityWaiting;
const _effectifAbsentColor = AppTheme.availabilityOut;
const _effectifNoResponseColor = AppTheme.availabilityUnknown;

extension _AdminSquadPlanEffectif on _AdminSquadPlanPageState {
  bool get _isInternalMatch =>
      _matches.any((match) => match.id == _selectedMatchId && match.isInternal);

  ConvocationStatus _desiredEffectifStatus(ConvocationPlayer player) =>
      _desiredEffectifStatuses[player.participantId] ??
      ConvocationStatus.notApplicable;

  List<ConvocationPlayer> get _convokedPlayers {
    final players = (_convocations?.players ?? const <ConvocationPlayer>[])
        .where(
          (player) => _postMatch
              ? _actualPresent.contains(player.participantId)
              : _desiredEffectifStatus(player) == ConvocationStatus.convoked,
        )
        .toList();
    players.sort(_convokedOrder);
    return players;
  }

  List<ConvocationPlayer> get _waitlistedPlayers {
    final players = (_convocations?.players ?? const <ConvocationPlayer>[])
        .where(
          (player) =>
              !player.isGuest &&
              _desiredEffectifStatus(player) == ConvocationStatus.notConvoked,
        )
        .toList();
    players.sort(_playerOrder);
    return players;
  }

  List<ConvocationPlayer> get _absentPlayers {
    final players = (_convocations?.players ?? const <ConvocationPlayer>[])
        .where(
          (player) =>
              player.isAbsent &&
              _desiredEffectifStatus(player) == ConvocationStatus.notApplicable,
        )
        .toList();
    players.sort(_playerOrder);
    return players;
  }

  List<ConvocationPlayer> get _unansweredPlayers {
    final players = (_convocations?.players ?? const <ConvocationPlayer>[])
        .where(
          (player) =>
              player.availabilityStatus == 'no_response' &&
              _desiredEffectifStatus(player) == ConvocationStatus.notApplicable,
        )
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

  Future<void> _setEffectifStatus(
    ConvocationPlayer player,
    ConvocationStatus status,
  ) async {
    if (_busy || _locked || player.isGuest) return;
    final current = _desiredEffectifStatus(player);
    if (current == status) return;
    // Sortir un joueur de la liste d'attente le prévient aussitôt, et la
    // notification ne peut pas être rappelée : c'est le seul geste de cet
    // écran qui mérite une confirmation.
    if (convocationPushWillFire(
      wasWaitlisted: player.convocationStatus == ConvocationStatus.notConvoked,
      becomesConvoked: status == ConvocationStatus.convoked,
      effectifWritten: _effectifWritten,
      postMatch: _postMatch,
    )) {
      final confirmed = await _confirmAction(
        title: 'Prévenir ${player.displayName} ?',
        actionLabel: 'Confirmer',
        actionIcon: Icons.notifications_active_outlined,
        content: Text(
          '${player.displayName} entre dans l’effectif : il reçoit tout de '
          'suite la notification « Tu es convoqué », s’il les a activées. '
          'Elle ne peut pas être rattrapée.',
        ),
      );
      if (!confirmed || !mounted) return;
      if (_busy || _locked || _desiredEffectifStatus(player) != current) return;
    }
    _updateState(() {
      if (status == ConvocationStatus.notApplicable) {
        _desiredEffectifStatuses.remove(player.participantId);
      } else {
        _desiredEffectifStatuses[player.participantId] = status;
      }
      _effectifRevision += 1;
    });
    _scheduleEffectifSave();
  }

  /// Programme l'écriture de l'effectif juste après le geste de l'admin.
  ///
  /// Le court délai évite d'écrire une fois par doigt qui glisse : plusieurs
  /// décisions enchaînées partent en une seule écriture.
  void _scheduleEffectifSave() {
    _effectifAutosave?.cancel();
    _effectifAutosave = Timer(
      const Duration(milliseconds: 700),
      () => unawaited(_persistEffectif()),
    );
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
            player.seasonPlayerId.isNotEmpty &&
            _desiredEffectifStatus(player) != ConvocationStatus.notApplicable)
          player.seasonPlayerId: _desiredEffectifStatus(player),
    };
  }

  /// Écrit l'effectif tel qu'il est à l'écran.
  ///
  /// Rien n'est rechargé : la réponse du serveur suffit à remettre l'écran à
  /// jour, et la composition en cours de préparation n'est pas perdue. Elle est
  /// simplement réajustée — un joueur qui rejoint arrive sur le banc, un joueur
  /// qui s'en va laisse son emplacement vide.
  Future<void> _persistEffectif({bool recoverOnError = true}) async {
    final convocations = _convocations;
    if (convocations == null) return;
    if (!_canSaveEffectifNow) {
      // Une écriture ou un chargement est déjà en cours : cette décision
      // repassera juste après, elle n'est pas perdue.
      if (_effectifSaving || _busy) _scheduleEffectifSave();
      return;
    }
    final limit = _validatedSquadLimit(showError: false);
    if (limit == null) return;

    _effectifAutosave?.cancel();
    final revision = _effectifRevision;
    _updateState(() => _effectifSaving = true);
    try {
      final updated =
          await ref.read(sportWaitlistRepositoryProvider).publishEffectif(
                matchId: convocations.matchId,
                squadSizeLimit: limit,
                decisions: _effectifDecisions(convocations),
                reason: 'Effectif enregistré depuis le match',
              );
      ref.invalidate(matchAvailabilityBoardProvider(convocations.matchId));
      if (!mounted || _selectedMatchId != convocations.matchId) return;
      _applyConvocations(updated,
          adoptDecisions: revision == _effectifRevision);
    } catch (error) {
      if (!mounted) return;
      _showMessage(humanizeError(error));
      // L'écriture a échoué : l'écran ne doit pas rester sur une décision que
      // le serveur a refusée. On repart de ce qu'il connaît, sauf si une
      // composition en cours d'édition risquait d'être perdue.
      if (recoverOnError && !_compositionDirty) {
        unawaited(_loadWorkspace(convocations.matchId));
      }
    } finally {
      if (mounted) _updateState(() => _effectifSaving = false);
    }
  }

  /// Réaligne l'écran sur l'effectif que le serveur vient de confirmer.
  void _applyConvocations(
    MatchConvocations convocations, {
    required bool adoptDecisions,
  }) {
    final composition = _postMatch
        ? _composition
        : _normalizeComposition(convocations, _composition, _goalkeeperIds);
    _updateState(() {
      _convocations = convocations;
      _composition = composition;
      if (adoptDecisions) {
        _desiredEffectifStatuses = _effectifStatusesFor(
          convocations: convocations,
          postMatch: _postMatch,
          actualPresent: _actualPresent,
        );
      }
    });
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
                'ser${reminders.noResponseCount > 1 ? 'ont' : 'a'} relancé'
                '${reminders.noResponseCount > 1 ? 's' : ''}. Les joueurs '
                'sans notifications activées seront signalés après l’envoi.'
            : 'La relance sera lancée si ce joueur a activé les notifications. '
                'Un second envoi est bloqué pendant dix minutes.',
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

      final messages = <String>[];
      if (result.createdCount > 0) {
        messages.add(
          'Relance lancée pour ${result.createdCount} joueur'
          '${result.createdCount > 1 ? 's' : ''}.',
        );
      }
      if (result.skippedNoSubscriptionCount > 0) {
        messages.add(
          '${result.skippedNoSubscriptionCount} joueur'
          '${result.skippedNoSubscriptionCount > 1 ? 's n’ont' : ' n’a'} '
          'pas activé les notifications.',
        );
      }
      if (result.skippedRecentCount > 0) {
        messages.add(
          '${result.skippedRecentCount} joueur'
          '${result.skippedRecentCount > 1 ? 's ont' : ' a'} déjà été relancé'
          '${result.skippedRecentCount > 1 ? 's' : ''} il y a moins de dix minutes.',
        );
      }
      _showMessage(
        messages.isEmpty ? 'Aucun joueur à relancer.' : messages.join(' '),
      );
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
    } finally {
      if (mounted) _updateState(() => _busy = false);
    }
  }

  void _showPlayerInfo(ConvocationPlayer player) {
    final status = player.availabilityStatus;
    final updatedAt = player.availabilityUpdatedAt;
    final (availabilityLabel, availabilityIcon) = switch (status) {
      'available' => ('Disponible', Icons.check_circle_outline),
      'absent' => ('Absent', Icons.cancel_outlined),
      _ => ('Sans réponse', Icons.schedule_outlined),
    };
    final availabilityColor = switch (status) {
      'available' => _effectifConvokedColor,
      'absent' => _effectifAbsentColor,
      _ => _effectifNoResponseColor,
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
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w400),
              ),
              const SizedBox(height: 16),
              _PlayerInfoRow(
                icon: availabilityIcon,
                color: availabilityColor,
                title: availabilityLabel,
                detail: availabilityDetail,
              ),
              if (!_isInternalMatch) ...[
                const SizedBox(height: 12),
                _PlayerInfoRow(
                  icon: Icons.hourglass_top_rounded,
                  color: _effectifWaitlistColor,
                  title: 'Liste d’attente',
                  detail: waitlistDetail,
                ),
                if (!player.isGuest) ...[
                  const SizedBox(height: 12),
                  _PlayerInfoRow(
                    icon: Icons.repeat_rounded,
                    color: _effectifWaitlistColor,
                    title: 'Nombre de tours en liste d’attente',
                    detail: '${player.currentSeasonWaitlistCount} fois',
                  ),
                ],
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
                if (!_isInternalMatch)
                  TextField(
                    controller: _limitController,
                    enabled: !_busy && !_locked,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Nombre de joueurs souhaité',
                      border: const OutlineInputBorder(),
                      errorText: _validatedSquadLimit(showError: false) == null
                          ? 'Saisis un nombre entre 1 et 30.'
                          : null,
                    ),
                    onChanged: (_) {
                      _updateState(() {});
                      _scheduleEffectifSave();
                    },
                  ),
                if (!_isInternalMatch && over) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${_convokedPlayers.length} joueurs pour une limite de $limit.',
                    style: const TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
                if (!_isInternalMatch) const SizedBox(height: 12),
                if (!_isInternalMatch)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.push('/admin/waitlist'),
                          icon: const Icon(Icons.format_list_numbered_rounded),
                          label: const Text(
                            'Voir la liste d’attente',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy || _locked ? null : _addGuest,
                          icon: const Icon(Icons.person_add_alt_1_outlined),
                          label: const Text(
                            'Ajouter un invité',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  )
                else
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
              _EffectifAvatarColumn(
                title: 'Convoqués',
                color: _effectifConvokedColor,
                icon: Icons.check_circle_outline,
                players: _convokedPlayers,
                acceptsDrops: true,
                draggable: true,
                onAccept: (player) =>
                    _setEffectifStatus(player, ConvocationStatus.convoked),
                onRemoveGuest: _removeGuestFromMatch,
                onShowInfo: _showPlayerInfo,
                locked: _locked || _busy,
              ),
              if (!_isInternalMatch)
                _EffectifAvatarColumn(
                  title: 'Liste d’attente',
                  color: _effectifWaitlistColor,
                  icon: Icons.hourglass_top_rounded,
                  players: _waitlistedPlayers,
                  acceptsDrops: true,
                  draggable: true,
                  onAccept: (player) =>
                      _setEffectifStatus(player, ConvocationStatus.notConvoked),
                  onShowInfo: _showPlayerInfo,
                  locked: _locked || _busy,
                ),
              _EffectifAvatarColumn(
                title: 'Absents',
                color: _effectifAbsentColor,
                icon: Icons.cancel_outlined,
                players: _absentPlayers,
                acceptsDrops: true,
                acceptsPlayer: (player) => player.isAbsent,
                draggable: true,
                onAccept: (player) =>
                    _setEffectifStatus(player, ConvocationStatus.notApplicable),
                onShowInfo: _showPlayerInfo,
                locked: _busy || _locked,
              ),
              _EffectifAvatarColumn(
                title: 'Sans réponse',
                color: _effectifNoResponseColor,
                icon: Icons.schedule_outlined,
                players: _unansweredPlayers,
                acceptsDrops: true,
                acceptsPlayer: (player) =>
                    player.availabilityStatus == 'no_response',
                draggable: true,
                onAccept: (player) =>
                    _setEffectifStatus(player, ConvocationStatus.notApplicable),
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
        const SizedBox(height: 16),
        if (!_locked)
          Text(
            _effectifSaving
                ? 'Enregistrement…'
                : 'Chaque changement est enregistré tout de suite.',
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
