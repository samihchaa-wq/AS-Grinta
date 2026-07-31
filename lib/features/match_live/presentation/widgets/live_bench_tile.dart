import 'package:as_grinta/core/widgets/drag_auto_scroll.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:flutter/material.dart';

/// Vignette d'un joueur sur le banc, avec le compteur 🔄 (nombre de fois sur
/// le banc). Reprend la même mécanique de glisser-déposer que la composition
/// pré-match (LongPressDraggable + DragAutoScroller).
class LiveBenchTile extends StatelessWidget {
  const LiveBenchTile({
    super.key,
    required this.entry,
    required this.draggable,
    this.timesBenched = 0,
    this.onTap,
  });

  final MatchCompositionEntry entry;
  final bool draggable;
  final int timesBenched;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Même taille que les marqueurs du terrain (FormationPitchEditor) pour
    // que le banc et les titulaires soient visuellement cohérents.
    final box = SizedBox(
      width: 48,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              PlayerAvatar(
                photoUrl: entry.photoUrl,
                name: entry.displayName,
                isGoalkeeper: entry.isGoalkeeper,
                size: 42,
              ),
              if (timesBenched > 0)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: SubstituteHistoryBadge(count: timesBenched),
                ),
            ],
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
    final tappable = onTap == null
        ? box
        : InkWell(
            borderRadius: BorderRadius.circular(12), onTap: onTap, child: box);
    if (!draggable) return tappable;
    final autoScroll = DragAutoScroller(context);
    return LongPressDraggable<MatchCompositionEntry>(
      data: entry,
      feedback: Material(color: Colors.transparent, child: box),
      childWhenDragging: Opacity(opacity: .3, child: box),
      onDragUpdate: (details) => autoScroll.update(details.globalPosition),
      onDragEnd: (_) => autoScroll.stop(),
      onDraggableCanceled: (_, __) => autoScroll.stop(),
      child: tappable,
    );
  }
}
