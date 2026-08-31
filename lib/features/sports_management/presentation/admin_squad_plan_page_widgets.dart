part of 'admin_squad_plan_page.dart';

class _EffectifTapSelection {
  _EffectifTapSelection._();

  static Object? _owner;
  static String? _matchId;
  static final ValueNotifier<ConvocationPlayer?> selectedPlayer =
      ValueNotifier<ConvocationPlayer?>(null);

  static ConvocationPlayer? selectedFor({
    required Object owner,
    required String? matchId,
  }) {
    if (!identical(_owner, owner) || _matchId != matchId) return null;
    return selectedPlayer.value;
  }

  static void toggle({
    required Object owner,
    required String? matchId,
    required ConvocationPlayer player,
  }) {
    final current = selectedFor(owner: owner, matchId: matchId);
    if (current?.participantId == player.participantId) {
      clear();
      return;
    }
    _owner = owner;
    _matchId = matchId;
    selectedPlayer.value = player;
  }

  static void clear() {
    _owner = null;
    _matchId = null;
    if (selectedPlayer.value != null) selectedPlayer.value = null;
  }
}

class _PlayerInfoRow extends StatelessWidget {
  const _PlayerInfoRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w400)),
              const SizedBox(height: 2),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _FormationDropdown extends StatelessWidget {
  const _FormationDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Dispositif',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final formation in footballFormations)
          DropdownMenuItem(value: formation.code, child: Text(formation.code)),
      ],
      onChanged: onChanged == null
          ? null
          : (value) {
              if (value != null) onChanged!(value);
            },
    );
  }
}

class _BenchBox extends StatelessWidget {
  const _BenchBox({
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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CompositionPlayerTile(
            entry: entry,
            onTap: draggable
                ? () => FormationPitchTapSelection.placePlayer(entry)
                : null,
          ),
          if (finishedBenchCount > 0)
            Positioned(
              top: 0,
              right: -2,
              child: SubstituteHistoryBadge(count: finishedBenchCount),
            ),
        ],
      ),
    );
    final selectableTile = FormationPitchTapSelectionHighlight(
      entry: entry,
      child: tile,
    );
    if (!draggable) return selectableTile;
    final autoScroll = DragAutoScroller(context);
    return LongPressDraggable<MatchCompositionEntry>(
      data: entry,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(type: MaterialType.transparency, child: tile),
      childWhenDragging: Opacity(opacity: .35, child: tile),
      onDragUpdate: (details) => autoScroll.update(details.globalPosition),
      onDragEnd: (_) => autoScroll.stop(),
      onDraggableCanceled: (_, __) => autoScroll.stop(),
      child: selectableTile,
    );
  }
}

class _GuestInput {
  const _GuestInput(this.firstName, this.lastName, this.goalkeeper);

  final String firstName;
  final String lastName;
  final bool goalkeeper;
}
