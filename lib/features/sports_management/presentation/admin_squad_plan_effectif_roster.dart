part of 'admin_squad_plan_page.dart';

/// Variante compacte de la gestion d'effectif : trois colonnes fixes, avec la
/// photo du joueur immédiatement à gauche de son prénom. Les interactions
/// restent identiques à l'ancien affichage (tap puis catégorie, glisser-déposer,
/// retrait d'un invité et relance individuelle).
class _EffectifAvatarColumn extends StatelessWidget {
  const _EffectifAvatarColumn({
    required this.title,
    required this.color,
    required this.icon,
    required this.players,
    required this.locked,
    this.acceptsDrops = false,
    this.acceptsPlayer,
    this.draggable = false,
    this.onAccept,
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
  final bool Function(ConvocationPlayer)? acceptsPlayer;
  final bool draggable;
  final ValueChanged<ConvocationPlayer>? onAccept;
  final ValueChanged<ConvocationPlayer>? onRemoveGuest;
  final ValueChanged<ConvocationPlayer>? onShowInfo;
  final VoidCallback? onRelanceAll;
  final ValueChanged<ConvocationPlayer>? onRelance;

  bool _canAccept(ConvocationPlayer player) =>
      acceptsDrops &&
      !locked &&
      !player.isGuest &&
      (acceptsPlayer?.call(player) ?? true);

  @override
  Widget build(BuildContext context) {
    final owner = context.findAncestorStateOfType<_AdminSquadPlanPageState>();
    final matchId = owner?._selectedMatchId;

    return ValueListenableBuilder<ConvocationPlayer?>(
      valueListenable: _EffectifTapSelection.selectedPlayer,
      builder: (context, _, __) {
        final selectedPlayer = owner == null
            ? null
            : _EffectifTapSelection.selectedFor(owner: owner, matchId: matchId);
        final canTapTarget =
            selectedPlayer != null && _canAccept(selectedPlayer);

        return DragTarget<ConvocationPlayer>(
          onWillAcceptWithDetails: (details) => _canAccept(details.data),
          onAcceptWithDetails: (details) {
            onAccept?.call(details.data);
            _EffectifTapSelection.clear();
          },
          builder: (context, candidates, rejected) {
            final highlightedTarget = candidates.isNotEmpty || canTapTarget;
            final section = AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  color.withValues(alpha: highlightedTarget ? .20 : .11),
                  Theme.of(context).colorScheme.surfaceContainer,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: highlightedTarget
                      ? color
                      : color.withValues(alpha: .52),
                  width: highlightedTarget ? 2 : 1,
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: color,
                                    fontWeight: FontWeight.w400,
                                  ),
                        ),
                      ),
                      if (onRelanceAll != null && players.isNotEmpty)
                        TextButton.icon(
                          onPressed: locked ? null : onRelanceAll,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(0, 34),
                          ),
                          icon: const Icon(
                            Icons.notifications_active_outlined,
                            size: 16,
                          ),
                          label: const Text('Relancer tous'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (players.isEmpty)
                    Text(
                      'Aucun joueur.',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    _EffectifAvatarGrid(
                      players: players,
                      color: color,
                      locked: locked,
                      draggable: !locked && draggable,
                      onRemoveGuest: onRemoveGuest,
                      onShowInfo: onShowInfo,
                      onRelance: onRelance,
                    ),
                ],
              ),
            );

            if (!canTapTarget) return section;
            return MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (owner == null) return;
                  final selected = _EffectifTapSelection.selectedFor(
                    owner: owner,
                    matchId: matchId,
                  );
                  if (selected == null || !_canAccept(selected)) return;
                  onAccept?.call(selected);
                  _EffectifTapSelection.clear();
                },
                child: section,
              ),
            );
          },
        );
      },
    );
  }
}

class _EffectifAvatarGrid extends StatelessWidget {
  const _EffectifAvatarGrid({
    required this.players,
    required this.color,
    required this.locked,
    required this.draggable,
    this.onRemoveGuest,
    this.onShowInfo,
    this.onRelance,
  });

  static const int _columns = 3;

  final List<ConvocationPlayer> players;
  final Color color;
  final bool locked;
  final bool draggable;
  final ValueChanged<ConvocationPlayer>? onRemoveGuest;
  final ValueChanged<ConvocationPlayer>? onShowInfo;
  final ValueChanged<ConvocationPlayer>? onRelance;

  Color _playerColor(ConvocationPlayer player) =>
      switch (player.availabilityStatus) {
        'absent' => _effectifAbsentColor,
        'no_response' => _effectifNoResponseColor,
        _ => color,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var row = 0; row < players.length; row += _columns) ...[
          if (row > 0) const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < _columns; column++) ...[
                if (column > 0) const SizedBox(width: 8),
                Expanded(
                  child: row + column < players.length
                      ? _playerCell(
                          context,
                          players[row + column],
                          _playerColor(players[row + column]),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _playerCell(
    BuildContext context,
    ConvocationPlayer player,
    Color playerColor,
  ) {
    final owner = context.findAncestorStateOfType<_AdminSquadPlanPageState>();
    return ValueListenableBuilder<ConvocationPlayer?>(
      valueListenable: _EffectifTapSelection.selectedPlayer,
      builder: (context, _, __) {
        final selectedPlayer = owner == null
            ? null
            : _EffectifTapSelection.selectedFor(
                owner: owner,
                matchId: owner._selectedMatchId,
              );
        final selected = selectedPlayer?.participantId == player.participantId;
        final onTap = player.isGuest
            ? (onRemoveGuest == null ? null : () => onRemoveGuest!(player))
            : locked || owner == null
                ? null
                : () => _EffectifTapSelection.toggle(
                      owner: owner,
                      matchId: owner._selectedMatchId,
                      player: player,
                    );

        final tile = _EffectifAvatarPlayerTile(
          key: ValueKey('effectif-player-${player.participantId}'),
          player: player,
          color: playerColor,
          selected: selected,
          onTap: onTap,
          onRelance: (player.isGuest || onRelance == null)
              ? null
              : () => onRelance!(player),
        );

        Widget content = Semantics(
          button: onTap != null,
          label: player.displayName,
          hint: onShowInfo == null ? null : 'Touchez pour sélectionner le joueur',
          child: tile,
        );

        if (draggable && !player.isGuest) {
          final autoScroll = DragAutoScroller(context);
          content = LongPressDraggable<ConvocationPlayer>(
            data: player,
            feedback: Material(
              type: MaterialType.transparency,
              child: SizedBox(width: 122, child: tile),
            ),
            childWhenDragging: Opacity(opacity: .30, child: tile),
            onDragUpdate: (details) => autoScroll.update(details.globalPosition),
            onDragEnd: (_) => autoScroll.stop(),
            onDraggableCanceled: (_, __) => autoScroll.stop(),
            child: content,
          );
        }
        return content;
      },
    );
  }
}

class _EffectifAvatarPlayerTile extends StatelessWidget {
  const _EffectifAvatarPlayerTile({
    super.key,
    required this.player,
    required this.color,
    required this.selected,
    this.onTap,
    this.onRelance,
  });

  final ConvocationPlayer player;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onRelance;

  @override
  Widget build(BuildContext context) {
    final selectionColor = selected ? AppTheme.accent : color;
    final tile = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          constraints: const BoxConstraints(minHeight: 39),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          decoration: BoxDecoration(
            color: selected
                ? selectionColor.withValues(alpha: .16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: selected
                ? Border.all(color: selectionColor.withValues(alpha: .85))
                : null,
          ),
          child: Row(
            children: [
              PlayerAvatar(
                photoUrl: player.photoUrl,
                name: player.shortName,
                isGoalkeeper: player.isGoalkeeper,
                size: 30,
                fallbackScale: .9,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  player.shortName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              if (player.isGuest && onTap != null)
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(Icons.close, size: 13, color: color),
                )
              else if (onRelance != null)
                Tooltip(
                  message: 'Relancer ${player.displayName}',
                  child: InkResponse(
                    onTap: onRelance,
                    radius: 15,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.notifications_active_outlined,
                        size: 14,
                        color: color,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return tile;
  }
}
