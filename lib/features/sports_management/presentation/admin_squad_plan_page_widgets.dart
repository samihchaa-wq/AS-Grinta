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
    final body = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '$title (${players.length})',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (onRelanceAll != null)
                Tooltip(
                  message: 'Relancer tous les sans réponse',
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: locked ? null : onRelanceAll,
                    icon: const Icon(Icons.notifications_active_outlined),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (players.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Aucun joueur.'),
            )
          else
            for (final player in players) ...[
              _EffectifPlayerTile(
                player: player,
                locked: locked,
                color: color,
                onToggle: onToggle == null ? null : () => onToggle!(player),
                onRemoveGuest:
                    onRemoveGuest == null ? null : () => onRemoveGuest!(player),
                onShowInfo:
                    onShowInfo == null ? null : () => onShowInfo!(player),
                onRelance: onRelance == null ||
                        player.availabilityStatus != 'no_response'
                    ? null
                    : () => onRelance!(player),
              ),
              const SizedBox(height: 7),
            ],
        ],
      ),
    );
    if (!acceptsDrops || onAccept == null) return body;
    return DragTarget<ConvocationPlayer>(
      onWillAcceptWithDetails: (details) => !locked && !details.data.isGuest,
      onAcceptWithDetails: (details) => onAccept!(details.data),
      builder: (context, candidates, rejected) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: candidates.isEmpty
            ? null
            : BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: .28),
                    blurRadius: 16,
                  ),
                ],
              ),
        child: body,
      ),
    );
  }
}

class _EffectifPlayerTile extends StatelessWidget {
  const _EffectifPlayerTile({
    required this.player,
    required this.locked,
    required this.color,
    this.onToggle,
    this.onRemoveGuest,
    this.onShowInfo,
    this.onRelance,
  });

  final ConvocationPlayer player;
  final bool locked;
  final Color color;
  final VoidCallback? onToggle;
  final VoidCallback? onRemoveGuest;
  final VoidCallback? onShowInfo;
  final VoidCallback? onRelance;

  @override
  Widget build(BuildContext context) {
    final card = Material(
      color: Colors.black.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onShowInfo,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          child: Row(
            children: [
              _EffectifPlayerAvatar(player: player, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (player.waitlistPosition != null)
                      Text(
                        'Liste d’attente · ${player.waitlistPosition}${player.waitlistPosition == 1 ? 'er' : 'e'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              if (onRelance != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Relancer ce joueur',
                  onPressed: locked ? null : onRelance,
                  icon: const Icon(Icons.notifications_active_outlined),
                ),
              if (player.isGuest && onRemoveGuest != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Retirer l’invité',
                  onPressed: locked ? null : onRemoveGuest,
                  icon: const Icon(Icons.person_remove_outlined),
                )
              else if (onToggle != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Changer de colonne',
                  onPressed: locked ? null : onToggle,
                  icon: const Icon(Icons.swap_horiz_rounded),
                ),
            ],
          ),
        ),
      ),
    );

    if (locked || player.isGuest || onToggle == null) return card;
    return LongPressDraggable<ConvocationPlayer>(
      data: player,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        type: MaterialType.transparency,
        child: SizedBox(width: 250, child: card),
      ),
      childWhenDragging: Opacity(opacity: .35, child: card),
      child: card,
    );
  }
}

class _EffectifPlayerAvatar extends StatelessWidget {
  const _EffectifPlayerAvatar({required this.player, required this.color});

  final ConvocationPlayer player;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: color.withValues(alpha: .18),
      child: player.isGuest
          ? const Icon(Icons.person_outline_rounded, size: 18)
          : Text(
              _initials(player.displayName),
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
    );
  }

  String _initials(String value) {
    final words = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      return words.first.substring(0, 1).toUpperCase();
    }
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
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
      value: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Dispositif',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final formation in footballFormations)
          DropdownMenuItem(
            value: formation.code,
            child: Text(formation.label),
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
    return LongPressDraggable<MatchCompositionEntry>(
      data: entry,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(type: MaterialType.transparency, child: tile),
      childWhenDragging: Opacity(opacity: .35, child: tile),
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
