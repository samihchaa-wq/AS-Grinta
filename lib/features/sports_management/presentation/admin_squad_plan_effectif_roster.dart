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
    this.countCoachApart = true,
    this.kitPhotos = const <String, String>{},
  });

  /// Portraits du maillot choisi pour ce match, coach compris. Un joueur sans
  /// variante garde sa photo France. `null` pendant le chargement : les
  /// portraits attendent alors au lieu d'afficher brièvement France.
  final Map<String, String>? kitPhotos;

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

  /// « 12 + coach » n'a de sens que là où les places comptent (convoqués).
  /// Ailleurs, l'entraîneur est compté comme un membre ordinaire, comme dans
  /// la vue joueur : « Sans réponse (18) » et non « 17 + coach ».
  final bool countCoachApart;

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
            final section = EffectifSectionFrame(
              title: title,
              countLabel: countCoachApart
                  ? effectifCountLabel(players)
                  : '${players.length}',
              color: color,
              icon: icon,
              highlighted: highlightedTarget,
              trailing: onRelanceAll != null && players.isNotEmpty
                  ? TextButton.icon(
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
                    )
                  : null,
              child: players.isEmpty
                  ? const EffectifEmptyLabel()
                  : kitPhotos == null
                      ? const SizedBox.shrink()
                      : _EffectifAvatarGrid(
                          players: players,
                          kitPhotos: kitPhotos!,
                          color: color,
                          locked: locked,
                          draggable: !locked && draggable,
                          onRemoveGuest: onRemoveGuest,
                          onShowInfo: onShowInfo,
                          onRelance: onRelance,
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
    required this.kitPhotos,
    required this.color,
    required this.locked,
    required this.draggable,
    this.onRemoveGuest,
    this.onShowInfo,
    this.onRelance,
  });

  final List<ConvocationPlayer> players;
  final Map<String, String> kitPhotos;
  final Color color;
  final bool locked;
  final bool draggable;
  final ValueChanged<ConvocationPlayer>? onRemoveGuest;
  final ValueChanged<ConvocationPlayer>? onShowInfo;
  final ValueChanged<ConvocationPlayer>? onRelance;

  Color _playerColor(ConvocationPlayer player) =>
      switch (player.availabilityStatus) {
        'available' => _effectifConvokedColor,
        'absent' => _effectifAbsentColor,
        'no_response' => _effectifNoResponseColor,
        _ => color,
      };

  @override
  Widget build(BuildContext context) {
    return EffectifAvatarGrid(
      children: [
        for (final player in players)
          _playerCell(context, player, _playerColor(player)),
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

        final reminder = owner?._reminders?.playerFor(player.seasonPlayerId);
        final tile = _EffectifAvatarPlayerTile(
          key: ValueKey('effectif-player-${player.participantId}'),
          player: player,
          photoUrl: player.isGuest
              ? player.photoUrl
              : kitPhotos[player.seasonPlayerId] ?? player.photoUrl,
          color: playerColor,
          selected: selected,
          onTap: onTap,
          onRelance: (player.isGuest || onRelance == null)
              ? null
              : () => onRelance!(player),
          manualReminderCount: reminder?.manualReminderCount ?? 0,
        );

        Widget content = Semantics(
          button: onTap != null,
          label: player.displayName,
          hint:
              onShowInfo == null ? null : 'Touche pour sélectionner le joueur',
          child: tile,
        );

        // Le coach ne se déplace pas d'une colonne à l'autre : il n'y a
        // aucune décision d'effectif à prendre pour lui, sa réponse décide.
        if (draggable && !player.isGuest && !player.isCoach) {
          final autoScroll = DragAutoScroller(context);
          content = LongPressDraggable<ConvocationPlayer>(
            data: player,
            feedback: Material(
              type: MaterialType.transparency,
              child: SizedBox(width: 122, child: tile),
            ),
            childWhenDragging: Opacity(opacity: .30, child: tile),
            onDragUpdate: (details) =>
                autoScroll.update(details.globalPosition),
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
    required this.photoUrl,
    required this.color,
    required this.selected,
    this.onTap,
    this.onRelance,
    this.manualReminderCount = 0,
  });

  final ConvocationPlayer player;
  final String? photoUrl;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onRelance;

  /// Nombre de relances faites par un admin pour ce match, affiché en petit
  /// sur la cloche. Rien n'est affiché tant qu'il vaut zéro.
  final int manualReminderCount;

  @override
  Widget build(BuildContext context) {
    return EffectifPlayerTile(
      photoUrl: photoUrl,
      name: player.shortName,
      lastName: player.lastName,
      isGoalkeeper: player.isGoalkeeper,
      isCoach: player.isCoach,
      color: color,
      selected: selected,
      selectionColor: AppTheme.accent,
      onTap: onTap,
      trailing: player.isGuest && onTap != null
          ? Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Icon(Icons.close, size: 13, color: color),
            )
          : onRelance != null
              ? Tooltip(
                  message: manualReminderCount > 0
                      ? 'Relancer ${player.displayName} '
                          '(déjà $manualReminderCount fois)'
                      : 'Relancer ${player.displayName}',
                  child: InkResponse(
                    onTap: onRelance,
                    radius: 15,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      // Le nombre de relances, lisible, à droite de la cloche.
                      // Rien tant que le joueur n'a pas été relancé.
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.notifications_active_outlined,
                            size: 14,
                            color: color,
                          ),
                          if (manualReminderCount > 0) ...[
                            const SizedBox(width: 2),
                            Text(
                              '$manualReminderCount',
                              style: TextStyle(fontSize: 13, color: color),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                )
              : null,
    );
  }
}
