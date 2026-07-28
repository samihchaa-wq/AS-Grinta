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
