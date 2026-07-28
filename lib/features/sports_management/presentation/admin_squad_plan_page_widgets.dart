part of 'admin_squad_plan_page.dart';

class _PublicationStatusCard extends StatelessWidget {
  const _PublicationStatusCard({
    required this.title,
    required this.detail,
    required this.pending,
  });

  final String title;
  final String detail;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final color = pending ? Colors.orange : const Color(0xFF168A52);
    final icon = pending ? Icons.edit_note_rounded : Icons.public_rounded;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(detail),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
          color: candidates.isNotEmpty
              ? color.withValues(alpha: .18)
              : color.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: candidates.isNotEmpty ? color : color.withValues(alpha: .35),
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
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final player in players)
                    _EffectifPlayerChip(
                      player: player,
                      color: color,
                      draggable: !locked && onToggle != null && !player.isGuest,
                      onTap: player.isGuest
                          ? (onRemoveGuest == null
                              ? null
                              : () => onRemoveGuest!(player))
                          : (onShowInfo == null
                              ? null
                              : () => onShowInfo!(player)),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _EffectifPlayerChip extends StatelessWidget {
  const _EffectifPlayerChip({
    required this.player,
    required this.color,
    required this.draggable,
    this.onTap,
  });

  final ConvocationPlayer player;
  final Color color;
  final bool draggable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = ActionChip(
      avatar: player.isGuest
          ? const Icon(Icons.person_add_alt_1_outlined, size: 16)
          : player.hasUnpublishedConvocationChange
              ? const Icon(Icons.edit_outlined, size: 16)
              : null,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            player.firstName.trim().isEmpty
                ? player.displayName
                : player.firstName.trim(),
          ),
          if (player.isGuest && onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.close, size: 15, color: color.withValues(alpha: .8)),
          ],
        ],
      ),
      onPressed: onTap,
      side: BorderSide(color: color.withValues(alpha: .55)),
      backgroundColor: color.withValues(alpha: .10),
    );
    if (!draggable) return chip;
    return LongPressDraggable<ConvocationPlayer>(
      data: player,
      feedback: Material(type: MaterialType.transparency, child: chip),
      childWhenDragging: Opacity(opacity: .3, child: chip),
      child: chip,
    );
  }
}

class _GuestInput {
  const _GuestInput(this.firstName, this.lastName, this.goalkeeper);

  final String firstName;
  final String lastName;
  final bool goalkeeper;
}

class _BenchBox extends StatelessWidget {
  const _BenchBox({required this.entry, required this.draggable});

  final MatchCompositionEntry entry;
  final bool draggable;

  @override
  Widget build(BuildContext context) {
    final box = SizedBox(
      width: 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayerAvatar(
            photoUrl: entry.photoUrl,
            name: entry.displayName,
            isGoalkeeper: entry.isGoalkeeper,
            size: 58,
          ),
          const SizedBox(height: 4),
          Text(
            entry.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    if (!draggable) return box;
    return LongPressDraggable<MatchCompositionEntry>(
      data: entry,
      feedback: Material(color: Colors.transparent, child: box),
      childWhenDragging: Opacity(opacity: .3, child: box),
      child: box,
    );
  }
}

class _FormationDropdown extends StatelessWidget {
  const _FormationDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final headerStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white54,
          fontWeight: FontWeight.w900,
          letterSpacing: .4,
        );
    final items = <DropdownMenuItem<String>>[];
    int? lastLine;
    for (final formation in footballFormations) {
      if (formation.defenderLine != lastLine) {
        lastLine = formation.defenderLine;
        items.add(
          DropdownMenuItem<String>(
            enabled: false,
            value: '__hdr_${formation.defenderLine}',
            child: Text(
              '${formation.defenderLine} DÉFENSEURS',
              style: headerStyle,
            ),
          ),
        );
      }
      items.add(
        DropdownMenuItem<String>(
          value: formation.code,
          child: Text(formation.code),
        ),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Dispositif',
        prefixIcon: Icon(Icons.grid_view_rounded),
        border: OutlineInputBorder(),
      ),
      items: items,
      onChanged: onChanged == null
          ? null
          : (selected) {
              if (selected == null || selected.startsWith('__hdr_')) return;
              onChanged!(selected);
            },
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
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(detail, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
