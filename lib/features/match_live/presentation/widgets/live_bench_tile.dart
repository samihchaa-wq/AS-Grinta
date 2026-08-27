import 'package:as_grinta/core/widgets/composition_drag.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/formation_pitch_editor.dart';
import 'package:flutter/material.dart';

/// Vignette d'un joueur sur le banc, avec le compteur 🔄 (nombre de fois sur
/// le banc). Reprend la même mécanique de glisser-déposer que la composition
/// pré-match ([CompositionDraggable]).
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
          Text(
            entry.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: metrics.nameFontSize,
              fontWeight: FontWeight.w800,
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
    if (!draggable) return tappable;
    return CompositionDraggable<MatchCompositionEntry>(
      data: entry,
      feedback: box,
      feedbackLift: metrics.height * .45,
      childWhenDragging: Opacity(opacity: .3, child: box),
      child: tappable,
    );
  }
}
