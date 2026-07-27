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

  int? _validatedSquadLimit() {
    final limit = int.tryParse(_limitController.text.trim());
    if (limit == null || limit < 1 || limit > 30) {
      _showMessage('Saisis une limite comprise entre 1 et 30.');
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
          player.seasonPlayerId:
              _desiredConvoked.contains(player.participantId)
                  ? ConvocationStatus.convoked
                  : ConvocationStatus.notConvoked,
    };
  }

  Future<bool> _saveEffectif() async {
    final convocations = _convocations;
    if (convocations == null || _busy || _locked) return false;
    final limit = _validatedSquadLimit();
    if (limit == null) return false;
    setState(() => _busy = true);
    try {
      await ref.read(sportWaitlistRepositoryProvider).saveEffectif(
            matchId: convocations.matchId,
            squadSizeLimit: limit,
            decisions: _effectifDecisions(convocations),
            reason: 'Brouillon d’effectif enregistré depuis le match',
          );
      await _loadWorkspace(convocations.matchId);
      ref.invalidate(matchAvailabilityBoardProvider(convocations.matchId));
      if (!mounted) return false;
      final count = _convokedPlayers.length;
      _showMessage(
        count > limit
            ? 'Brouillon enregistré : $count joueurs pour une limite de $limit. Rien n’est encore publié.'
            : 'Brouillon d’effectif enregistré. Rien n’est encore publié.',
      );
      return true;
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publishEffectif() async {
    final convocations = _convocations;
    if (convocations == null || _busy || _locked) return;
    final limit = _validatedSquadLimit();
    if (limit == null) return;
    final convoked = _convokedPlayers;
    final waitlisted = _waitlistedPlayers;
    final overLimit = convoked.length > limit;
    final confirmed = await _confirmAction(
      title: convocations.isPublished
          ? 'Publier les modifications ?'
          : 'Publier les convocations ?',
      actionLabel: convocations.isPublished ? 'Mettre à jour' : 'Publier',
      actionIcon: Icons.campaign_outlined,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${convoked.length} convoqué${convoked.length > 1 ? 's' : ''} · '
            '${waitlisted.length} en liste d’attente · limite $limit.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Cette action rendra les décisions visibles par les joueurs. La composition restera privée jusqu’à sa propre publication.',
          ),
          if (overLimit) ...[
            const SizedBox(height: 12),
            Text(
              'Attention : l’effectif dépasse la limite de ${convoked.length - limit} joueur${convoked.length - limit > 1 ? 's' : ''}.',
              style: const TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(sportWaitlistRepositoryProvider).publishEffectif(
            matchId: convocations.matchId,
            squadSizeLimit: limit,
            decisions: _effectifDecisions(convocations),
            reason: 'Convocations publiées explicitement depuis le match',
          );
      await _loadWorkspace(convocations.matchId);
      ref.invalidate(matchAvailabilityBoardProvider(convocations.matchId));
      if (mounted) _showMessage('Convocations publiées.');
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
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

    setState(() => _busy = true);
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
      setState(() => _reminders = updated);
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
      if (mounted) setState(() => _busy = false);
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
    final publishedDetail = switch (player.publishedConvocationStatus) {
      ConvocationStatus.convoked => 'Convoqué dans la publication actuelle',
      ConvocationStatus.notConvoked => 'Non convoqué dans la publication actuelle',
      ConvocationStatus.notApplicable => 'Aucune décision publiée',
    };
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
                icon: Icons.campaign_outlined,
                color: player.hasUnpublishedConvocationChange
                    ? Colors.orange
                    : const Color(0xFF168A52),
                title: player.hasUnpublishedConvocationChange
                    ? 'Modification non publiée'
                    : 'Convocation publiée',
                detail: publishedDetail,
              ),
              const SizedBox(height: 12),
              _PlayerInfoRow(
                icon: Icons.hourglass_top_rounded,
                color: const Color(0xFFE08A00),
                title: 'Liste d’attente',
                detail: waitlistDetail,
              ),
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
    setState(() => _busy = true);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildEffectif() {
    final convocations = _convocations!;
    final limit = int.tryParse(_limitController.text) ?? 14;
    final over = _convokedPlayers.length > limit;
    final hasPending = _effectifHasPendingPublication;
    final statusTitle = _effectifDirty
        ? 'Modifications non enregistrées'
        : convocations.hasUnpublishedChanges
            ? 'Brouillon enregistré, non publié'
            : convocations.isPublished
                ? 'Convocations publiées'
                : 'Aucune convocation publiée';
    final statusDetail = _effectifDirty
        ? 'Enregistre le brouillon ou publie directement les décisions actuelles.'
        : convocations.hasUnpublishedChanges
            ? 'Les joueurs voient encore la précédente publication.'
            : convocations.isPublished
                ? 'Version ${convocations.convocationVersion} visible par les joueurs.'
                : 'Les joueurs ne voient encore aucune décision de convocation.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PublicationStatusCard(
          title: statusTitle,
          detail: statusDetail,
          pending: hasPending || !convocations.isPublished,
        ),
        const SizedBox(height: 14),
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
                  'Glisse-le pour changer de colonne. Les changements restent '
                  'privés tant que tu ne publies pas les convocations.',
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
                    '${_convokedPlayers.length} convoqués pour une limite de $limit. Une confirmation sera demandée avant publication.',
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
        if (_canConsultWaitlist) ...[
          OutlinedButton.icon(
            onPressed: _busy ? null : () => context.push('/admin/waitlist'),
            icon: const Icon(Icons.format_list_numbered_rounded),
            label: const Text('Consulter la liste d’attente'),
          ),
          const SizedBox(height: 14),
        ],
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
        OutlinedButton.icon(
          onPressed: _busy || _locked || !_effectifDirty ? null : _saveEffectif,
          icon: const Icon(Icons.save_outlined),
          label: Text(
            _effectifDirty ? 'Enregistrer le brouillon' : 'Brouillon enregistré',
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _busy ||
                  _locked ||
                  (!hasPending && convocations.isPublished)
              ? null
              : _publishEffectif,
          icon: const Icon(Icons.campaign_outlined),
          label: Text(
            convocations.isPublished
                ? hasPending
                    ? 'Publier les modifications'
                    : 'Convocations publiées'
                : 'Publier les convocations',
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
}
