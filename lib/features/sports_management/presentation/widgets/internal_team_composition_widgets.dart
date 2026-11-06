part of 'internal_team_composition_view.dart';

class _PaperTeams extends StatelessWidget {
  const _PaperTeams({
    required this.team1Name,
    required this.team2Name,
    required this.team1Controller,
    required this.team2Controller,
    required this.team1Jersey,
    required this.team2Jersey,
    required this.team1,
    required this.team2,
    required this.editable,
    required this.selectedParticipantId,
    required this.onAssignTeam1,
    required this.onAssignTeam2,
    required this.onJersey1,
    required this.onJersey2,
    required this.onPlayerTap,
  });

  final String team1Name;
  final String team2Name;
  final TextEditingController? team1Controller;
  final TextEditingController? team2Controller;
  final JerseyOption team1Jersey;
  final JerseyOption team2Jersey;
  final List<InternalCompositionEntry> team1;
  final List<InternalCompositionEntry> team2;
  final bool editable;
  final String? selectedParticipantId;
  final VoidCallback onAssignTeam1;
  final VoidCallback onAssignTeam2;
  final ValueChanged<JerseyOption> onJersey1;
  final ValueChanged<JerseyOption> onJersey2;
  final ValueChanged<InternalCompositionEntry> onPlayerTap;

  @override
  Widget build(BuildContext context) {
    final hasSelected = selectedParticipantId != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _PaperTeamColumn(
            name: team1Name,
            teamNo: 1,
            controller: team1Controller,
            jersey: team1Jersey,
            unavailableJersey: team2Jersey,
            entries: team1,
            editable: editable,
            hasSelectedPlayer: hasSelected,
            selectedParticipantId: selectedParticipantId,
            onJerseyTap: onAssignTeam1,
            onJerseySelected: onJersey1,
            onPlayerTap: onPlayerTap,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _PaperTeamColumn(
            name: team2Name,
            teamNo: 2,
            controller: team2Controller,
            jersey: team2Jersey,
            unavailableJersey: team1Jersey,
            entries: team2,
            editable: editable,
            hasSelectedPlayer: hasSelected,
            selectedParticipantId: selectedParticipantId,
            onJerseyTap: onAssignTeam2,
            onJerseySelected: onJersey2,
            onPlayerTap: onPlayerTap,
          ),
        ),
      ],
    );
  }
}

class _PaperTeamColumn extends StatelessWidget {
  const _PaperTeamColumn({
    required this.name,
    required this.teamNo,
    required this.controller,
    required this.jersey,
    required this.unavailableJersey,
    required this.entries,
    required this.editable,
    required this.hasSelectedPlayer,
    required this.selectedParticipantId,
    required this.onJerseyTap,
    required this.onJerseySelected,
    required this.onPlayerTap,
  });

  final String name;
  final int teamNo;
  final TextEditingController? controller;
  final JerseyOption jersey;
  final JerseyOption unavailableJersey;
  final List<InternalCompositionEntry> entries;
  final bool editable;
  final bool hasSelectedPlayer;
  final String? selectedParticipantId;
  final VoidCallback onJerseyTap;
  final ValueChanged<JerseyOption> onJerseySelected;
  final ValueChanged<InternalCompositionEntry> onPlayerTap;

  @override
  Widget build(BuildContext context) {
    final controllerName = controller?.text.trim();
    final semanticName = controllerName != null && controllerName.isNotEmpty
        ? controllerName
        : name;
    final countLabel = entries.isEmpty
        ? ''
        : '${entries.length} joueur${entries.length > 1 ? 's' : ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PaperJerseyAssignmentTile(
          semanticName: semanticName,
          jersey: jersey,
          unavailableJersey: unavailableJersey,
          playerCountLabel: countLabel,
          editable: editable,
          assignmentEnabled: editable && hasSelectedPlayer,
          onTap: onJerseyTap,
          onJerseySelected: onJerseySelected,
        ),
        const SizedBox(height: 8),
        if (editable && controller != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: controller,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'Équipe $teamNo',
                counterText: '',
                isDense: true,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              semanticName,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.surface.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.outline.withValues(alpha: .3)),
          ),
          child: entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(2),
                  child: Text(
                    'Aucun joueur.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : Column(
                  children: [
                    for (var index = 0; index < entries.length; index += 1)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: index == entries.length - 1 ? 0 : 6,
                        ),
                        child: _PlayerChip(
                          entry: entries[index],
                          editable: editable,
                          selected: selectedParticipantId ==
                              entries[index].participantId,
                          onTap: () => onPlayerTap(entries[index]),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _PaperJerseyAssignmentTile extends StatelessWidget {
  const _PaperJerseyAssignmentTile({
    required this.semanticName,
    required this.jersey,
    required this.unavailableJersey,
    required this.playerCountLabel,
    required this.editable,
    required this.assignmentEnabled,
    required this.onTap,
    required this.onJerseySelected,
  });

  final String semanticName;
  final JerseyOption jersey;
  final JerseyOption unavailableJersey;
  final String playerCountLabel;
  final bool editable;
  final bool assignmentEnabled;
  final VoidCallback onTap;
  final ValueChanged<JerseyOption> onJerseySelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: assignmentEnabled,
      label: [
        semanticName,
        if (playerCountLabel.isNotEmpty) playerCountLabel,
        'maillot ${jersey.label}',
      ].join(', '),
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: assignmentEnabled
                ? AppTheme.accent
                : AppTheme.outline.withValues(alpha: .3),
            width: assignmentEnabled ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: assignmentEnabled ? onTap : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Image.asset(jersey.assetPath, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            if (playerCountLabel.isNotEmpty)
              Positioned(
                left: 7,
                bottom: 7,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTheme.surface.withValues(alpha: .92),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppTheme.outline.withValues(alpha: .35),
                    ),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    child: Text(
                      playerCountLabel,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              ),
            if (editable)
              Positioned(
                top: 2,
                right: 2,
                child: PopupMenuButton<JerseyOption>(
                  tooltip: 'Choisir le maillot',
                  initialValue: jersey,
                  onSelected: onJerseySelected,
                  itemBuilder: (context) => [
                    for (final option in JerseyOption.values)
                      PopupMenuItem<JerseyOption>(
                        value: option,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 34,
                              height: 34,
                              child: Image.asset(
                                option.assetPath,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              option == unavailableJersey
                                  ? '${option.label} · échanger'
                                  : option.label,
                            ),
                          ],
                        ),
                      ),
                  ],
                  icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InternalTeamCard extends StatelessWidget {
  const _InternalTeamCard({
    required this.name,
    required this.teamNo,
    required this.jersey,
    required this.unavailableJersey,
    required this.entries,
    required this.editable,
    required this.canReceiveSelected,
    required this.onAssignSelected,
    required this.onJerseySelected,
    required this.onDroppedOnSlot,
    required this.onRemoveFromField,
    required this.finishedBenchCounts,
    this.controller,
  });

  final String name;
  final int teamNo;
  final JerseyOption jersey;
  final JerseyOption unavailableJersey;
  final List<InternalCompositionEntry> entries;
  final bool editable;
  final bool canReceiveSelected;
  final VoidCallback onAssignSelected;
  final ValueChanged<JerseyOption> onJerseySelected;
  final void Function(MatchCompositionEntry, FootballFormationSlot)
      onDroppedOnSlot;
  final ValueChanged<MatchCompositionEntry> onRemoveFromField;
  final Map<String, int> finishedBenchCounts;
  final TextEditingController? controller;

  MatchCompositionEntry _classic(InternalCompositionEntry entry) {
    return MatchCompositionEntry(
      participantId: entry.participantId,
      seasonPlayerId: entry.seasonPlayerId ?? '',
      guestPlayerId: entry.guestPlayerId,
      displayName: entry.displayName,
      lastInitial: entry.lastInitial,
      isGuest: entry.isGuest,
      isGoalkeeper: entry.isGoalkeeper,
      zone: MatchCompositionZone.fromWire(entry.zone),
      x: entry.x,
      y: entry.y,
      slotLabel: entry.slotLabel,
      photoUrl: entry.photoUrl,
      sortOrder: entry.sortOrder,
      availabilityStatus: 'available',
      convocationStatus: 'convoked',
      selectionStatus: switch (entry.zone) {
        'field' => 'starter',
        'bench' => 'substitute',
        _ => 'undecided',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final formation = internalDefaultFormationForPlayerCount(entries.length);
    final field = entries
        .where((entry) => entry.zone == 'field')
        .map(_classic)
        .toList(growable: false);
    final bench = entries
        .where((entry) => entry.zone == 'bench')
        .map(_classic)
        .toList(growable: false);
    final waiting =
        entries.where((entry) => entry.zone == 'available').toList();
    final semanticName = controller?.text.trim().isNotEmpty == true
        ? controller!.text.trim()
        : name;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _JerseyTarget(
                  semanticName: semanticName,
                  jersey: jersey,
                  unavailableJersey: unavailableJersey,
                  editable: editable,
                  assignmentEnabled: canReceiveSelected,
                  onAssignSelected: onAssignSelected,
                  onJerseySelected: onJerseySelected,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: editable && controller != null
                      ? TextField(
                          controller: controller,
                          maxLength: 40,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Équipe $teamNo',
                            counterText: '',
                            isDense: true,
                          ),
                        )
                      : Text(
                          semanticName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (formation != null)
              Text(
                'Dispositif ${formation.code}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            const SizedBox(height: 10),
            if (formation != null)
              FormationPitchEditor(
                slots: formation.slots,
                entries: field,
                editable: editable,
                finishedBenchCounts: finishedBenchCounts,
                onDroppedOnSlot: onDroppedOnSlot,
                onRemoveFromField: onRemoveFromField,
              )
            else
              Container(
                height: 220,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.surface.withValues(alpha: .45),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.outline.withValues(alpha: .3),
                  ),
                ),
                child: Text(
                  entries.isEmpty
                      ? 'Aucun joueur dans cette équipe.'
                      : 'Le terrain sera disponible dès que l’équipe contient un joueur.',
                  textAlign: TextAlign.center,
                ),
              ),
            if (bench.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Remplaçants (${bench.length})',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in bench)
                    _ClassicBenchBox(
                      entry: entry,
                      draggable: editable,
                      finishedBenchCount:
                          finishedBenchCounts[entry.participantId] ?? 0,
                    ),
                ],
              ),
            ],
            if (waiting.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'À placer (${waiting.length})',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in waiting)
                    _ClassicBenchBox(
                      entry: _classic(entry),
                      draggable: editable,
                      finishedBenchCount:
                          finishedBenchCounts[entry.participantId] ?? 0,
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

class _ClassicBenchBox extends StatelessWidget {
  const _ClassicBenchBox({
    required this.entry,
    required this.draggable,
    required this.finishedBenchCount,
  });

  final MatchCompositionEntry entry;
  final bool draggable;
  final int finishedBenchCount;

  @override
  Widget build(BuildContext context) {
    final tile = SizedBox(
      width: 70,
      child: Align(
        alignment: Alignment.topLeft,
        heightFactor: 1,
        child: CompositionPlayerTile(
          entry: entry,
          onTap: draggable
              ? () => FormationPitchTapSelection.placePlayer(entry)
              : null,
          cornerBadge: finishedBenchCount > 0
              ? SubstituteHistoryBadge(count: finishedBenchCount)
              : null,
        ),
      ),
    );
    final highlighted = FormationPitchTapSelectionHighlight(
      entry: entry,
      child: tile,
    );
    if (!draggable) return highlighted;
    return LongPressDraggable<MatchCompositionEntry>(
      data: entry,
      feedback: Material(type: MaterialType.transparency, child: tile),
      childWhenDragging: Opacity(opacity: .35, child: tile),
      child: highlighted,
    );
  }
}

class _JerseyTarget extends StatelessWidget {
  const _JerseyTarget({
    required this.semanticName,
    required this.jersey,
    required this.unavailableJersey,
    required this.editable,
    required this.assignmentEnabled,
    required this.onAssignSelected,
    required this.onJerseySelected,
  });

  final String semanticName;
  final JerseyOption jersey;
  final JerseyOption unavailableJersey;
  final bool editable;
  final bool assignmentEnabled;
  final VoidCallback onAssignSelected;
  final ValueChanged<JerseyOption> onJerseySelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        children: [
          Positioned.fill(
            child: Semantics(
              button: assignmentEnabled,
              label: '$semanticName, maillot ${jersey.label}',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: assignmentEnabled ? onAssignSelected : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppTheme.surface.withValues(alpha: .55),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: assignmentEnabled
                            ? AppTheme.accent
                            : AppTheme.outline.withValues(alpha: .3),
                        width: assignmentEnabled ? 2 : 1,
                      ),
                    ),
                    child: Image.asset(jersey.assetPath, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ),
          if (editable)
            Positioned(
              right: 0,
              top: 0,
              child: PopupMenuButton<JerseyOption>(
                tooltip: 'Choisir le maillot',
                initialValue: jersey,
                onSelected: onJerseySelected,
                itemBuilder: (context) => [
                  for (final option in JerseyOption.values)
                    PopupMenuItem(
                      value: option,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 30,
                            height: 30,
                            child: Image.asset(option.assetPath),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            option == unavailableJersey
                                ? '${option.label} · échanger'
                                : option.label,
                          ),
                        ],
                      ),
                    ),
                ],
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              ),
            ),
        ],
      ),
    );
  }
}

class _GroupedUnassignedPools extends StatelessWidget {
  const _GroupedUnassignedPools({
    required this.defenders,
    required this.midfielders,
    required this.attackers,
    required this.other,
    required this.editable,
    required this.selectedParticipantId,
    required this.canReceiveSelected,
    required this.onPoolTap,
    required this.onPlayerTap,
  });

  final List<InternalCompositionEntry> defenders;
  final List<InternalCompositionEntry> midfielders;
  final List<InternalCompositionEntry> attackers;
  final List<InternalCompositionEntry> other;
  final bool editable;
  final String? selectedParticipantId;
  final bool canReceiveSelected;
  final VoidCallback onPoolTap;
  final ValueChanged<InternalCompositionEntry> onPlayerTap;

  @override
  Widget build(BuildContext context) {
    final groups = <(String, List<InternalCompositionEntry>)>[
      ('Défenseurs', defenders),
      ('Milieux', midfielders),
      ('Attaquants', attackers),
      ('Autres', other),
    ];

    if (groups.every((group) => group.$2.isEmpty)) {
      return _WaitingPool(
        key: const ValueKey('internal-unassigned-pool'),
        entries: const [],
        editable: editable,
        selectedParticipantId: selectedParticipantId,
        canReceiveSelected: canReceiveSelected,
        onPoolTap: onPoolTap,
        onPlayerTap: onPlayerTap,
        emptyLabel: 'Tous les joueurs sont répartis.',
      );
    }

    return GestureDetector(
      key: const ValueKey('internal-unassigned-pool'),
      behavior: HitTestBehavior.opaque,
      onTap: canReceiveSelected ? onPoolTap : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final group in groups)
            if (group.$2.isNotEmpty) ...[
              Text(
                '${group.$1} (${group.$2.length})',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              _WaitingPool(
                entries: group.$2,
                editable: editable,
                selectedParticipantId: selectedParticipantId,
                canReceiveSelected: false,
                onPoolTap: onPoolTap,
                onPlayerTap: onPlayerTap,
                emptyLabel: '',
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _WaitingPool extends StatelessWidget {
  const _WaitingPool({
    super.key,
    required this.entries,
    required this.editable,
    required this.selectedParticipantId,
    required this.canReceiveSelected,
    required this.onPoolTap,
    required this.onPlayerTap,
    required this.emptyLabel,
  });

  final List<InternalCompositionEntry> entries;
  final bool editable;
  final String? selectedParticipantId;
  final bool canReceiveSelected;
  final VoidCallback onPoolTap;
  final ValueChanged<InternalCompositionEntry> onPlayerTap;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canReceiveSelected ? onPoolTap : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: canReceiveSelected
                ? AppTheme.accent
                : AppTheme.outline.withValues(alpha: .3),
            width: canReceiveSelected ? 2 : 1,
          ),
        ),
        child: entries.isEmpty
            ? Text(emptyLabel, style: Theme.of(context).textTheme.bodySmall)
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in entries)
                    _PlayerChip(
                      entry: entry,
                      editable: editable,
                      selected: selectedParticipantId == entry.participantId,
                      onTap: () => onPlayerTap(entry),
                    ),
                ],
              ),
      ),
    );
  }
}

class _PlayerChip extends StatelessWidget {
  const _PlayerChip({
    required this.entry,
    required this.editable,
    required this.selected,
    required this.onTap,
  });

  final InternalCompositionEntry entry;
  final bool editable;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: selected
            ? AppTheme.accent.withValues(alpha: .16)
            : AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? AppTheme.accent
              : AppTheme.outline.withValues(alpha: .5),
          width: selected ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayerAvatar(
            photoUrl: entry.photoUrl,
            name: entry.displayName,
            lastName: entry.lastInitial,
            isGoalkeeper: entry.isGoalkeeper,
            size: 28,
          ),
          const SizedBox(width: 8),
          Text(entry.displayName),
        ],
      ),
    );
    if (!editable) return chip;
    return Semantics(
      button: true,
      selected: selected,
      label: entry.displayName,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: chip,
      ),
    );
  }
}
