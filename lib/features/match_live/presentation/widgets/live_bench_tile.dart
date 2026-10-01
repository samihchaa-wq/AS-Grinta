import 'package:as_grinta/core/widgets/drag_auto_scroll.dart';
import 'package:as_grinta/features/match_live/domain/substitution_salvos.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/substitution_salvo_frame.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/formation_pitch_editor.dart';
import 'package:flutter/material.dart';

/// Vignette d'un joueur sur le banc, avec le compteur 🔄 (nombre de fois sur
/// le banc, suivi de la série de sa dernière sortie : « 2.1 »). Reprend la même mécanique de glisser-déposer que la composition
/// pré-match (LongPressDraggable + DragAutoScroller).
class LiveBenchTile extends StatelessWidget {
  const LiveBenchTile({
    super.key,
    required this.entry,
    required this.draggable,
    required this.metrics,
    this.timesBenched = 0,
    this.lastExit,
    this.onTap,
    this.namesOnly = false,
    this.outlineColor,
  });

  final MatchCompositionEntry entry;
  final bool draggable;

  /// Dimensions calculées depuis la largeur du terrain affiché à côté : un
  /// remplaçant occupe exactement la même place qu'un titulaire.
  final FormationMarkerMetrics metrics;

  final int timesBenched;

  /// Repère de la dernière sortie du joueur. `null` s'il n'est jamais sorti
  /// du terrain (remplaçant au coup d'envoi) : la pastille affiche « 1.0 ».
  final SubstitutionExitMark? lastExit;
  final VoidCallback? onTap;

  /// Prénom seul, sans pastille d'initiales ni photo (en direct).
  final bool namesOnly;

  /// Contour autour du prénom (remplaçant qui va entrer, dépôt en cours).
  final Color? outlineColor;

  @override
  Widget build(BuildContext context) {
    if (namesOnly) return _buildNameOnly(context);
    final box = SizedBox(
      width: metrics.width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...[
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
                    child: SubstituteHistoryBadge(
                      count: timesBenched,
                      label: liveBenchLabel(lastExit, timesBenched),
                      color: switch (lastExit) {
                        final exit? =>
                          substitutionSalvoColorAt(exit.colorIndex),
                        null => substitutionStartColor,
                      },
                    ),
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

  /// Prénom seul, avec le repère « passage.série » collé dessous, centré dans
  /// la place qu'occupait la pastille. Le cadre de sélection et le contour
  /// épousent le prénom, pas toute la place.
  Widget _buildNameOnly(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            entry.displayName,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: metrics.nameFontSize * 1.15,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        if (timesBenched > 0)
          SubstituteHistoryBadge(
            count: timesBenched,
            label: liveBenchLabel(lastExit, timesBenched),
            color: switch (lastExit) {
              final exit? => substitutionSalvoColorAt(exit.colorIndex),
              null => substitutionStartColor,
            },
          ),
      ],
    );
    final outlined = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: outlineColor ?? Colors.transparent,
          width: 2,
        ),
      ),
      child: content,
    );

    void handleTap() {
      if (FormationPitchTapSelection.placePlayer(entry)) return;
      onTap?.call();
    }

    final tappable = !draggable && onTap == null
        ? outlined
        : InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: handleTap,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            child: outlined,
          );
    Widget sized(Widget child) => SizedBox(
          width: metrics.width,
          height: metrics.avatarSize + 2 + metrics.nameHeight,
          child: Center(child: child),
        );
    final selectable = sized(
      FormationPitchTapSelectionHighlight(entry: entry, child: tappable),
    );
    if (!draggable) return selectable;
    final autoScroll = DragAutoScroller(context);
    return LongPressDraggable<MatchCompositionEntry>(
      data: entry,
      feedback: Material(color: Colors.transparent, child: sized(content)),
      childWhenDragging: Opacity(opacity: .3, child: sized(content)),
      onDragUpdate: (details) => autoScroll.update(details.globalPosition),
      onDragEnd: (_) => autoScroll.stop(),
      onDraggableCanceled: (_, __) => autoScroll.stop(),
      child: selectable,
    );
  }
}
