part of 'admin_squad_plan_page.dart';

extension _AdminSquadPlanComposition on _AdminSquadPlanPageState {
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
      return _rescueOrphans(
        baseline.copyWith(
          entries: [
            for (final entry in baseline.entries)
              entry.canBeSelected
                  ? entry.moveTo(MatchCompositionZone.bench)
                  : entry.moveTo(MatchCompositionZone.notSelected),
          ],
        ),
      );
    }
    final savedById = {
      for (final entry in saved.entries) entry.participantId: entry,
    };
    return _rescueOrphans(
      saved.copyWith(
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
                photoUrl: previous.photoUrl ?? base.photoUrl,
                goals: previous.goals,
                isMotm: previous.isMotm,
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
      ),
    );
  }

  MatchComposition _normalizePostMatchComposition(
    SportMatchFinalization finalization,
    MatchComposition? saved,
  ) {
    final baseline = MatchComposition.initialFromFinalization(
      finalization: finalization,
    );
    if (saved == null) return baseline;
    final savedById = {
      for (final entry in saved.entries) entry.participantId: entry,
    };
    return _rescueOrphans(
      saved.copyWith(
        entries: [
          for (final base in baseline.entries)
            if (savedById[base.participantId] case final previous?)
              MatchCompositionEntry(
                participantId: base.participantId,
                seasonPlayerId: base.seasonPlayerId,
                guestPlayerId: base.guestPlayerId,
                displayName: base.displayName,
                isGuest: base.isGuest,
                isGoalkeeper: base.isGoalkeeper,
                zone: base.canBeSelected
                    ? previous.zone == MatchCompositionZone.field
                        ? MatchCompositionZone.field
                        : MatchCompositionZone.bench
                    : MatchCompositionZone.notSelected,
                x: base.canBeSelected &&
                        previous.zone == MatchCompositionZone.field
                    ? previous.x
                    : null,
                y: base.canBeSelected &&
                        previous.zone == MatchCompositionZone.field
                    ? previous.y
                    : null,
                slotLabel: previous.slotLabel,
                photoUrl: base.photoUrl ?? previous.photoUrl,
                goals: base.goals,
                isMotm: base.isMotm,
                sortOrder: previous.sortOrder,
                availabilityStatus: base.availabilityStatus,
                convocationStatus: base.convocationStatus,
                selectionStatus: base.canBeSelected
                    ? previous.zone == MatchCompositionZone.field
                        ? 'starter'
                        : 'substitute'
                    : 'not_selected',
              )
            else
              base,
        ],
      ),
    );
  }

  MatchComposition _rescueOrphans(MatchComposition composition) {
    final formation = formationForCode(composition.formationCode);
    final slots = formation.slots;
    final field = composition.entriesFor(MatchCompositionZone.field);
    final used = List<bool>.filled(slots.length, false);
    final placement = <String, Offset>{};
    final orphans = <MatchCompositionEntry>[];
    for (final entry in field) {
      final position = Offset(entry.x ?? .5, entry.y ?? .5);
      var bestIndex = -1;
      var bestDistance = 0.08;
      for (var index = 0; index < slots.length; index += 1) {
        if (used[index]) continue;
        final distance = (position - slots[index].position).distance;
        if (distance < bestDistance) {
          bestDistance = distance;
          bestIndex = index;
        }
      }
      if (bestIndex >= 0) {
        used[bestIndex] = true;
        placement[entry.participantId] = slots[bestIndex].position;
      } else {
        orphans.add(entry);
      }
    }
    if (orphans.isEmpty) {
      return composition.copyWith(formationCode: formation.code);
    }
    final ordered = [
      ...orphans.where((entry) => entry.isGoalkeeper),
      ...orphans.where((entry) => !entry.isGoalkeeper),
    ];
    final freeSlots = [
      for (var index = 0; index < slots.length; index += 1)
        if (!used[index]) index,
    ];
    final overflow = <String>{};
    var next = 0;
    for (final entry in ordered) {
      if (next < freeSlots.length) {
        placement[entry.participantId] = slots[freeSlots[next]].position;
        next += 1;
      } else {
        overflow.add(entry.participantId);
      }
    }
    final benchBase = composition.entriesFor(MatchCompositionZone.bench).length;
    var benchExtra = 0;
    return composition.copyWith(
      formationCode: formation.code,
      entries: [
        for (final entry in composition.entries)
          if (placement.containsKey(entry.participantId))
            _entryWithStatus(
              entry,
              MatchCompositionZone.field,
              x: placement[entry.participantId]!.dx,
              y: placement[entry.participantId]!.dy,
            )
          else if (overflow.contains(entry.participantId))
            _entryWithStatus(
              entry,
              MatchCompositionZone.bench,
              sortOrder: benchBase + benchExtra++,
            )
          else
            entry,
      ],
    );
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
      photoUrl: entry.photoUrl,
      goals: entry.goals,
      isMotm: entry.isMotm,
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

  void _applyFormation(String code) {
    final composition = _composition;
    if (composition == null || _compositionLocked) return;
    if (formationForCode(composition.formationCode).code == code) return;
    final slots = formationForCode(code).slots;
    final field = composition.entriesFor(MatchCompositionZone.field);
    final ordered = [
      ...field.where((entry) => entry.isGoalkeeper),
      ...field.where((entry) => !entry.isGoalkeeper),
    ];
    final placement = <String, Offset>{};
    final overflow = <String>{};
    for (var index = 0; index < ordered.length; index += 1) {
      if (index < slots.length) {
        placement[ordered[index].participantId] = slots[index].position;
      } else {
        overflow.add(ordered[index].participantId);
      }
    }
    final benchBase = composition.entriesFor(MatchCompositionZone.bench).length;
    var benchExtra = 0;
    setState(() {
      _composition = composition.copyWith(
        formationCode: code,
        hasUnpublishedChanges: true,
        entries: [
          for (final entry in composition.entries)
            if (placement.containsKey(entry.participantId))
              _entryWithStatus(
                entry,
                MatchCompositionZone.field,
                x: placement[entry.participantId]!.dx,
                y: placement[entry.participantId]!.dy,
              )
            else if (overflow.contains(entry.participantId))
              _entryWithStatus(
                entry,
                MatchCompositionZone.bench,
                sortOrder: benchBase + benchExtra++,
              )
            else
              entry,
        ],
      );
    });
  }

  void _dropOnSlot(MatchCompositionEntry moving, FootballFormationSlot slot) {
    final composition = _composition;
    if (composition == null || _compositionLocked) return;
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
    });
  }

  void _moveToBench(MatchCompositionEntry moving) {
    final composition = _composition;
    if (composition == null || _compositionLocked) return;
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
    });
  }

  MatchComposition _compositionReadyToSave() {
    final composition = _composition!;
    final currentConvoked = _postMatch
        ? _actualPresent
        : {for (final player in _convokedPlayers) player.participantId};
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

  Future<bool> _confirmCompositionPublication(MatchComposition ready) {
    final fieldCount = ready.entriesFor(MatchCompositionZone.field).length;
    final benchCount = ready.entriesFor(MatchCompositionZone.bench).length;
    final limit = int.tryParse(_limitController.text) ??
        _convocations?.squadSizeLimit ??
        14;
    final selectedCount = fieldCount + benchCount;
    final overLimit = selectedCount > limit;
    return _confirmAction(
      title: ready.isPublished
          ? 'Mettre à jour la composition ?'
          : 'Publier la composition ?',
      actionLabel: ready.isPublished ? 'Mettre à jour' : 'Publier',
      actionIcon: Icons.campaign_outlined,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$fieldCount titulaire${fieldCount > 1 ? 's' : ''} · '
            '$benchCount remplaçant${benchCount > 1 ? 's' : ''}.',
          ),
          const SizedBox(height: 12),
          const Text(
            'La composition deviendra immédiatement visible par les joueurs. Les convocations ne seront pas modifiées par cette action.',
          ),
          if (overLimit) ...[
            const SizedBox(height: 12),
            Text(
              'Attention : $selectedCount joueurs sont sélectionnés pour une limite de $limit.',
              style: const TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<MatchComposition?> _saveComposition({required bool publish}) async {
    final composition = _composition;
    if (composition == null || _compositionLocked) return null;
    if (!_postMatch && !_effectifReadyForComposition) {
      _showMessage('Publie d’abord les convocations.');
      return null;
    }
    final ready = _compositionReadyToSave();
    if (publish) {
      final confirmed = await _confirmCompositionPublication(ready);
      if (!confirmed || !mounted) return null;
    }

    setState(() => _busy = true);
    try {
      final repository = ref.read(matchCompositionRepositoryProvider);
      final limit = int.tryParse(_limitController.text) ??
          _convocations?.squadSizeLimit ??
          14;
      final selectedCount =
          ready.entriesFor(MatchCompositionZone.field).length +
              ready.entriesFor(MatchCompositionZone.bench).length;
      final allowException = selectedCount > limit;
      late final MatchComposition result;
      if (_postMatch) {
        result = await repository.createPostMatchComposition(
          composition: ready,
          allowSquadSizeException: allowException,
          reason: 'Composition réelle publiée après finalisation du match',
        );
      } else {
        final saved = await repository.saveComposition(
          composition: ready,
          allowSquadSizeException: allowException,
          reason: publish
              ? 'Préparation de la publication de la composition'
              : 'Brouillon de composition',
        );
        result = publish
            ? await repository.publishComposition(
                matchId: ready.matchId,
                allowSquadSizeException: allowException,
                reason: 'Composition publiée explicitement depuis le match',
              )
            : saved;
      }
      if (!mounted) return result;
      setState(() {
        _composition = result;
        if (_postMatch) _compositionExisted = true;
      });
      ref.invalidate(publishedMatchCompositionProvider(ready.matchId));
      _showMessage(
        publish || _postMatch
            ? 'Composition publiée.'
            : 'Brouillon de composition enregistré.',
      );
      return result;
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildComposition() {
    final composition = _composition!;
    final field = composition.entriesFor(MatchCompositionZone.field);
    final bench = composition.entriesFor(MatchCompositionZone.bench)
      ..removeWhere((entry) => !_desiredConvoked.contains(entry.participantId));
    final effectifReady = _effectifReadyForComposition;
    final hasPendingComposition = composition.hasUnpublishedChanges;
    final canPublish = !_compositionLocked &&
        (!composition.isPublished || hasPendingComposition);

    final statusTitle = !effectifReady
        ? 'Convocations à publier avant la composition'
        : hasPendingComposition
            ? 'Brouillon de composition non publié'
            : composition.isPublished
                ? 'Composition publiée'
                : 'Composition non publiée';
    final statusDetail = !effectifReady
        ? 'Reviens dans Effectif, puis publie les convocations pour déverrouiller cette étape.'
        : hasPendingComposition
            ? 'Les joueurs voient encore la précédente composition.'
            : composition.isPublished
                ? 'Version ${composition.version} visible par les joueurs.'
                : 'Prépare le terrain et le banc avant publication.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PublicationStatusCard(
          title: statusTitle,
          detail: statusDetail,
          pending: !effectifReady ||
              hasPendingComposition ||
              !composition.isPublished,
        ),
        const SizedBox(height: 14),
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
                Text(
                  _postMatch
                      ? 'Choisis un dispositif, puis glisse les joueurs réellement présents sur les postes affichés.'
                      : 'Choisis un dispositif, puis glisse les joueurs convoqués sur les postes affichés. Le brouillon reste privé.',
                ),
                const SizedBox(height: 14),
                _FormationDropdown(
                  value: formationForCode(composition.formationCode).code,
                  onChanged: _compositionLocked ? null : _applyFormation,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: FormationPitchEditor(
            slots: formationForCode(composition.formationCode).slots,
            entries: field,
            editable: !_compositionLocked,
            onDroppedOnSlot: _dropOnSlot,
            onRemoveFromField: _moveToBench,
          ),
        ),
        const SizedBox(height: 14),
        DragTarget<MatchCompositionEntry>(
          onWillAcceptWithDetails: (details) => !_compositionLocked,
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
                    Wrap(
                      spacing: 12,
                      runSpacing: 14,
                      children: [
                        for (final entry in bench)
                          _BenchBox(
                            entry: entry,
                            draggable: !_compositionLocked,
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (!_postMatch) ...[
          OutlinedButton.icon(
            onPressed: _compositionLocked || !hasPendingComposition
                ? null
                : () => _saveComposition(publish: false),
            icon: const Icon(Icons.save_outlined),
            label: Text(
              hasPendingComposition
                  ? 'Enregistrer le brouillon'
                  : 'Brouillon enregistré',
            ),
          ),
          const SizedBox(height: 10),
        ],
        FilledButton.icon(
          onPressed: canPublish ? () => _saveComposition(publish: true) : null,
          icon: const Icon(Icons.campaign_outlined),
          label: Text(
            _postMatch && _compositionExisted
                ? 'Composition publiée'
                : composition.isPublished
                    ? hasPendingComposition
                        ? 'Publier les modifications'
                        : 'Composition publiée'
                    : 'Publier la composition',
          ),
        ),
        if (_postMatch && _compositionExisted)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Composition verrouillée : une composition existe déjà pour ce match.',
            ),
          )
        else if (_locked && !_postMatch)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Finalise d’abord le match pour utiliser les joueurs réellement présents.',
            ),
          ),
      ],
    );
  }
}
