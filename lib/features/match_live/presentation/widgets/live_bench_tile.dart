import 'package:as_grinta/core/widgets/drag_auto_scroll.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/formation_pitch_editor.dart';
import 'package:flutter/material.dart';

/// Vignette d'un joueur sur le banc, avec le compteur 🔄 (nombre de fois sur
/// le banc). Reprend la même mécanique de glisser-déposer que la composition
/// pré-match (LongPressDraggable + DragAutoScroller).
class LiveBenchTile extends StatelessWidget {
  const LiveBenchTile({
    super.key,
    required this.entry,
    required this.draggable,
    required this.metrics,
    this.timesBenched = 0,
    this.onTap,
  });

  final MatchCompositionEntry entry;
  final bool draggable;

  /// Dimensions calculées depuis la largeur du terrain affiché à côté : un
  /// remplaçant occupe exactement la même place qu'un titulaire.
  final FormationMarkerMetrics metrics;

  final int timesBenched;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = SizedBox(
      width: metrics.width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              PlayerAvatar(
                photoUrl: entry.photoUrl,
                name: entry.displayName,
                lastName: entry.lastInitial,
                isGoalkeeper: entry.isGoalkeeper,
                size: metrics.avatarSize,
              ),
              if (timesBenched > 0)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: SubstituteHistoryBadge(count: timesBenched),
                ),
            ],
          ),
          const SizedBox(height: 2),
          // La colonne du banc est collée au bord de l'écran : le prénom ne
          // peut pas déborder comme sur le terrain. Il est donc réduit juste
          // ce qu'il faut plutôt que coupé (« Franç… »).
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              entry.displayName,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: metrics.nameFontSize,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );

    void handleTap() {
      if (FormationPitchTapSelection.placePlayer(entry)) return;
      onTap?.call();
    }

    final tappable = !draggable && onTap == null
        ? box
        : InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: handleTap,
            child: box,
          );
    final selectableTile = FormationPitchTapSelectionHighlight(
      entry: entry,
      child: tappable,
    );
    if (!draggable) return selectableTile;
    final autoScroll = DragAutoScroller(context);
    return LongPressDraggable<MatchCompositionEntry>(
      data: entry,
      feedback: Material(color: Colors.transparent, child: box),
      childWhenDragging: Opacity(opacity: .3, child: box),
      onDragUpdate: (details) => autoScroll.update(details.globalPosition),
      onDragEnd: (_) => autoScroll.stop(),
      onDraggableCanceled: (_, __) => autoScroll.stop(),
      child: selectableTile,
    );
  }
}
