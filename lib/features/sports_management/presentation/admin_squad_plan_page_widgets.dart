part of 'admin_squad_plan_page.dart';

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
    this.onRemoveGuest,
    this.onShowInfo,
    this.onRelanceAll,
    this.onRelance,
  });

  final String title;
  final Color color;
  final IconData icon;
  final List<ConvocationPlayer> players;
  final bool locked;
  final bool acceptsDrops;
  final ValueChanged<ConvocationPlayer>? onAccept;
  final ValueChanged<ConvocationPlayer>? onToggle;
  final ValueChanged<ConvocationPlayer>? onRemoveGuest;
  final ValueChanged<ConvocationPlayer>? onShowInfo;
  final VoidCallback? onRelanceAll;
  final ValueChanged<ConvocationPlayer>? onRelance;

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
          color: Color.alphaBlend(
            color.withValues(alpha: candidates.isNotEmpty ? .22 : .13),
            Theme.of(context).colorScheme.surfaceContainer,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: candidates.isNotEmpty ? color : color.withValues(alpha: .55),
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
                if (onRelanceAll != null && players.isNotEmpty)
                  TextButton.icon(
                    onPressed: locked ? null : onRelanceAll,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(
                      Icons.notifications_active_outlined,
                      size: 16,
                    ),
                    label: const Text('Relancer tous'),
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
              _EffectifPlayerGrid(
                players: players,
                color: color,
                locked: locked,
                draggable: !locked && onToggle != null,
                onRemoveGuest: onRemoveGuest,
                onShowInfo: onShowInfo,
                onRelance: onRelance,
              ),
          ],
        ),
      ),
    );
  }
}

class _EffectifPlayerGrid extends StatelessWidget {
  const _EffectifPlayerGrid({
    required this.players,
    required this.color,
    required this.locked,
    required this.draggable,
    this.onRemoveGuest,
    this.onShowInfo,
    this.onRelance,
  });

  final List<ConvocationPlayer> players;
  final Color color;
  final bool locked;
  final bool draggable;
  final ValueChanged<ConvocationPlayer>? onRemoveGuest;
  final ValueChanged<ConvocationPlayer>? onShowInfo;
  final ValueChanged<ConvocationPlayer>? onRelance;

  Widget _chip(ConvocationPlayer player) => _EffectifPlayerChip(
        player: player,
        color: color,
        draggable: draggable && !player.isGuest,
        onTap: player.isGuest
            ? (onRemoveGuest == null ? null : () => onRemoveGuest!(player))
            : (onShowInfo == null ? null : () => onShowInfo!(player)),
        onRelance: (player.isGuest || onRelance == null)
            ? null
            : () => onRelance!(player),
      );

  static const int _columns = 4;

  @override
  Widget build(BuildContext context) {
    // Les pastilles de relance débordent au-dessus et à droite de chaque
    // puce : sans marge supplémentaire, elles chevauchent le nom du joueur
    // suivant (colonne) ou du dessus (ligne).
    final gap = onRelance != null ? 16.0 : 5.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < players.length; i += _columns) ...[
          if (i > 0) SizedBox(height: gap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var col = 0; col < _columns; col++) ...[
                if (col > 0) SizedBox(width: gap),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: i + col < players.length
                        ? _chip(players[i + col])
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _EffectifPlayerChip extends StatelessWidget {
  const _EffectifPlayerChip({
    required this.player,
    required this.color,
    required this.draggable,
    this.onTap,
    this.onRelance,
  });

  final ConvocationPlayer player;
  final Color color;
  final bool draggable;
  final VoidCallback? onTap;
  final VoidCallback? onRelance;

  @override
  Widget build(BuildContext context) {
    final chip = ActionChip(
      avatar: player.isGuest
          ? const Icon(Icons.person_add_alt_1_outlined, size: 15)
          : null,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              player.shortName,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (player.isGuest && onTap != null) ...[
            const SizedBox(width: 3),
            Icon(Icons.close, size: 14, color: color),
          ],
        ],
      ),
      onPressed: onTap,
      side: BorderSide(color: color.withValues(alpha: .72)),
      backgroundColor: Color.alphaBlend(
        color.withValues(alpha: .24),
        Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    Widget content = chip;
    if (draggable) {
      final autoScroll = DragAutoScroller(context);
      content = LongPressDraggable<ConvocationPlayer>(
        data: player,
        feedback: Material(type: MaterialType.transparency, child: chip),
        childWhenDragging: Opacity(opacity: .3, child: chip),
        onDragUpdate: (details) => autoScroll.update(details.globalPosition),
        onDragEnd: (_) => autoScroll.stop(),
        onDraggableCanceled: (_, __) => autoScroll.stop(),
        child: chip,
      );
    }
    if (onRelance == null) return content;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        content,
        Positioned(
          top: -10,
          right: -10,
          child: Tooltip(
            message: 'Relancer ${player.displayName}',
            child: Material(
              color: color,
              shape: const CircleBorder(),
              elevation: 1,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRelance,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.notifications_active_rounded,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
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
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
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
          DropdownMenuItem(
            value: formation.code,
            child: Text(formation.code),
          ),
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
          CompositionPlayerTile(entry: entry),
          if (finishedBenchCount > 0)
            Positioned(
              top: 0,
              right: -2,
              child: SubstituteHistoryBadge(count: finishedBenchCount),
            ),
        ],
      ),
    );
    if (!draggable) return tile;
    final autoScroll = DragAutoScroller(context);
    return LongPressDraggable<MatchCompositionEntry>(
      data: entry,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(type: MaterialType.transparency, child: tile),
      childWhenDragging: Opacity(opacity: .35, child: tile),
      onDragUpdate: (details) => autoScroll.update(details.globalPosition),
      onDragEnd: (_) => autoScroll.stop(),
      onDraggableCanceled: (_, __) => autoScroll.stop(),
      child: tile,
    );
  }
}

class _GuestInput {
  const _GuestInput(this.firstName, this.lastName, this.goalkeeper);

  final String firstName;
  final String lastName;
  final bool goalkeeper;
}
