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
    _updateState(() {
      _composition = composition.copyWith(
        formationCode: code,
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
      _compositionDirty = true;
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
    _updateState(() {
      _composition = composition.copyWith(
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
    if (composition == null || _compositionLocked) return;
    final benchCount =
        composition.entriesFor(MatchCompositionZone.bench).length;
    _updateState(() {
      _composition = composition.copyWith(
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

  /// Les convoqués tels que la simulation les voit.
  List<SimulationCandidate> _simulationCandidates(
    MatchComposition composition,
  ) {
    return [
      for (final entry in composition.entries)
        if (_desiredEffectifStatuses[entry.participantId] ==
            ConvocationStatus.convoked)
          SimulationCandidate(
            participantId: entry.participantId,
            displayName: entry.displayName,
            benchCount: _finishedBenchCounts[entry.participantId] ?? 0,
            profile: _positionProfiles[
                _canonicalPlayerIds[entry.seasonPlayerId] ?? ''],
            isGuest: entry.isGuest,
            isGoalkeeper: entry.isGoalkeeper,
          ),
    ];
  }

  /// Propose un onze à partir des postes de référence des joueurs.
  ///
  /// La simulation ne fait que remplir l'écran : rien n'est envoyé au serveur
  /// tant que l'admin n'a pas appuyé sur Enregistrer, et tout reste
  /// déplaçable.
  Future<void> _simulateComposition() async {
    final composition = _composition;
    if (composition == null || _compositionLocked || _postMatch) return;

    if (composition.fieldCount > 0) {
      final confirmed = await _confirmAction(
        title: 'Simuler une composition',
        content: Text(
          'Les ${composition.fieldCount} joueurs déjà placés sur le terrain '
          'seront repositionnés. Le dispositif '
          '${formationForCode(composition.formationCode).code} est conservé.',
        ),
        actionLabel: 'Simuler',
        actionIcon: Icons.auto_awesome_outlined,
      );
      if (!confirmed || !mounted) return;
    }

    final formation = formationForCode(composition.formationCode);
    final simulation = simulateComposition(
      slots: formation.slots,
      candidates: _simulationCandidates(composition),
    );

    final placedSlots = {
      for (final placement in simulation.placements)
        placement.candidate.participantId: placement.slot,
    };
    final benchOrder = {
      for (var index = 0; index < simulation.bench.length; index += 1)
        simulation.bench[index].participantId: index,
    };

    _updateState(() {
      _composition = composition.copyWith(
        entries: [
          for (final entry in composition.entries)
            if (placedSlots[entry.participantId] case final slot?)
              _entryWithStatus(
                entry,
                MatchCompositionZone.field,
                x: slot.position.dx,
                y: slot.position.dy,
              )
            else if (benchOrder[entry.participantId] case final order?)
              _entryWithStatus(
                entry,
                MatchCompositionZone.bench,
                sortOrder: order,
              )
            else
              _entryWithStatus(entry, MatchCompositionZone.notSelected),
        ],
      );
      _compositionDirty = true;
    });
    _showMessage(_simulationSummary(simulation));
  }

  String _simulationSummary(SimulatedComposition simulation) {
    final titulaires = simulation.placements.length;
    final parts = <String>[
      '$titulaires ${titulaires > 1 ? 'titulaires placés' : 'titulaire placé'}',
      '${simulation.bench.length} sur le banc',
    ];
    if (simulation.emptySlots.isNotEmpty) {
      final labels = simulation.emptySlots.map((slot) => slot.label).join(', ');
      parts.add('poste${simulation.emptySlots.length > 1 ? 's' : ''} '
          'sans joueur : $labels');
    }
    final stretched = simulation.stretchedPlacements;
    if (stretched.isNotEmpty) {
      final names = stretched
          .map((placement) =>
              '${placement.candidate.displayName} (${placement.slot.label})')
          .join(', ');
      parts.add('hors poste habituel : $names');
    }
    return '${parts.join(' · ')}. À toi d’ajuster.';
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

  Future<void> _persistComposition() async {
    final composition = _composition;
    if (composition == null || _compositionLocked || !_compositionDirty) {
      return;
    }
    if (!_postMatch && !_effectifReadyForComposition) {
      _showMessage('L’effectif doit être enregistré avant la composition.');
      return;
    }
    final ready = _compositionReadyToSave();
    _updateState(() => _busy = true);
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
        result = _compositionExisted
            ? await repository.updatePostMatchComposition(
                composition: ready,
                allowSquadSizeException: allowException,
                reason: 'Composition réelle enregistrée',
              )
            : await repository.createPostMatchComposition(
                composition: ready,
                allowSquadSizeException: allowException,
                reason: 'Composition réelle enregistrée',
              );
      } else {
        await repository.saveComposition(
          composition: ready,
          allowSquadSizeException: allowException,
          reason: 'Composition enregistrée',
        );
        result = await repository.publishComposition(
          matchId: ready.matchId,
          allowSquadSizeException: allowException,
          reason: 'Composition enregistrée',
        );
      }
      if (!mounted) return;
      _updateState(() {
        _composition = result;
        _compositionDirty = false;
        if (_postMatch) _compositionExisted = true;
      });
      ref.invalidate(publishedMatchCompositionProvider(ready.matchId));
      _showMessage('Composition enregistrée.');
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
    } finally {
      if (mounted) _updateState(() => _busy = false);
    }
  }

  Widget _buildComposition() {
    final composition = _composition!;
    final field = composition.entriesFor(MatchCompositionZone.field);
    final bench = composition.entriesFor(MatchCompositionZone.bench)
      ..removeWhere(
        (entry) =>
            _desiredEffectifStatuses[entry.participantId] !=
            ConvocationStatus.convoked,
      );
    final effectifReady = _effectifReadyForComposition;

    if (!effectifReady && !_postMatch) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Enregistre d’abord l’effectif pour préparer la composition.',
          ),
        ),
      );
    }

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
                Text(
                  _postMatch
                      ? 'Choisis le dispositif réellement joué, puis appuie sur Enregistrer.'
                      : 'Choisis un dispositif, glisse les joueurs sur les postes, puis appuie sur Enregistrer.',
                ),
                const SizedBox(height: 14),
                _FormationDropdown(
                  value: formationForCode(composition.formationCode).code,
                  onChanged: _compositionLocked ? null : _applyFormation,
                ),
                if (!_postMatch) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _compositionLocked ? null : _simulateComposition,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('Simuler une composition'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Place les convoqués à leur poste habituel, en '
                    'titularisant en priorité ceux qui ont le plus souvent '
                    'commencé sur le banc. Tout reste modifiable.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
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
            finishedBenchCounts: _postMatch ? const {} : _finishedBenchCounts,
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
                            finishedBenchCount: _postMatch
                                ? 0
                                : _finishedBenchCounts[entry.participantId] ??
                                    0,
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _compositionLocked || !_compositionDirty
              ? null
              : _persistComposition,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Enregistrer'),
        ),
        if (_locked && !_postMatch)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('Composition verrouillée au coup d’envoi.'),
          ),
      ],
    );
  }
}
