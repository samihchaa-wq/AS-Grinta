import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/drag_auto_scroll.dart';
import 'package:as_grinta/core/widgets/grinta_pitch.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:flutter/material.dart';

const List<({Offset source, Offset target})> _legacyFlat442DisplayMap = [
  (source: Offset(.50, .95), target: Offset(.50, .86)),
  (source: Offset(.15, .75), target: Offset(.14, .68)),
  (source: Offset(.38, .80), target: Offset(.38, .70)),
  (source: Offset(.62, .80), target: Offset(.62, .70)),
  (source: Offset(.85, .75), target: Offset(.86, .68)),
  (source: Offset(.15, .50), target: Offset(.14, .42)),
  (source: Offset(.38, .55), target: Offset(.38, .42)),
  (source: Offset(.62, .55), target: Offset(.62, .42)),
  (source: Offset(.85, .50), target: Offset(.86, .42)),
  (source: Offset(.35, .25), target: Offset(.36, .17)),
  (source: Offset(.65, .25), target: Offset(.64, .17)),
];

bool _usesLegacyFlat442Layout(List<MatchCompositionEntry> entries) {
  if (entries.length != _legacyFlat442DisplayMap.length) return false;
  final positions = entries
      .where((entry) => entry.x != null && entry.y != null)
      .map((entry) => Offset(entry.x!, entry.y!))
      .toList();
  if (positions.length != _legacyFlat442DisplayMap.length) return false;
  return _legacyFlat442DisplayMap.every(
    (mapping) => positions.any(
      (position) => (position - mapping.source).distance <= .025,
    ),
  );
}

Offset _displayPosition(
  MatchCompositionEntry entry, {
  required bool legacyFlat442,
}) {
  final raw = Offset(entry.x ?? .5, entry.y ?? .5);
  if (!legacyFlat442) return raw;
  for (final mapping in _legacyFlat442DisplayMap) {
    if ((raw - mapping.source).distance <= .025) return mapping.target;
  }
  return raw;
}

/// Dimensions d'un marqueur de joueur, dérivées de la largeur du terrain.
///
/// Le banc du Tableau Blanc s'appuie sur les mêmes valeurs : sans cela ses
/// vignettes gardaient une taille fixe et paraissaient plus grosses que les
/// titulaires dès que le terrain se réduisait pour laisser la place au banc.
///
/// Les valeurs elles-mêmes viennent du terrain partagé : il n'existe qu'une
/// seule définition d'une vignette de joueur dans l'application.
class FormationMarkerMetrics {
  const FormationMarkerMetrics(this.pitch);

  /// Taille des marqueurs pour un terrain large de `pitchWidth`.
  factory FormationMarkerMetrics.forPitch(double pitchWidth) =>
      FormationMarkerMetrics(GrintaPitchMetrics.forPitch(pitchWidth));

  final GrintaPitchMetrics pitch;

  double get width => pitch.slotWidth;

  double get height => pitch.slotHeight;

  double get avatarSize => pitch.jerseyDiameter;

  double get nameFontSize => pitch.nameFontSize;
}

class FormationPitchEditor extends StatelessWidget {
  const FormationPitchEditor({
    super.key,
    required this.slots,
    required this.entries,
    required this.onDroppedOnSlot,
    required this.onRemoveFromField,
    this.editable = true,
    this.finishedBenchCounts = const {},
    this.markerMetrics,
    this.formationLabel,
  });

  final List<FootballFormationSlot> slots;
  final List<MatchCompositionEntry> entries;
  final void Function(MatchCompositionEntry entry, FootballFormationSlot slot)
      onDroppedOnSlot;
  final ValueChanged<MatchCompositionEntry> onRemoveFromField;
  final bool editable;

  /// Nombre de fois où chaque joueur (par participantId) a déjà été noté
  /// remplaçant dans un match terminé.
  final Map<String, int> finishedBenchCounts;

  /// Taille imposée des marqueurs. Renseignée quand un autre bloc (le banc du
  /// Tableau Blanc) doit afficher exactement les mêmes vignettes ; sinon elle
  /// est déduite de la largeur réelle du terrain.
  final FormationMarkerMetrics? markerMetrics;

  /// Dispositif affiché en bas à gauche du terrain (« 4-4-2 », « 3-5-2 »…).
  final String? formationLabel;

  MatchCompositionEntry? _entryFor(
    FootballFormationSlot slot,
    bool legacyFlat442,
  ) {
    MatchCompositionEntry? closest;
    var distance = double.infinity;
    for (final entry in entries) {
      final current = _displayPosition(entry, legacyFlat442: legacyFlat442);
      final candidate = (current - slot.position).distance;
      if (candidate < distance) {
        distance = candidate;
        closest = entry;
      }
    }
    return distance < .12 ? closest : null;
  }

  @override
  Widget build(BuildContext context) {
    final legacyFlat442 = _usesLegacyFlat442Layout(entries);
    return GrintaPitchSurface(
      formationLabel: formationLabel,
      builder: (context, size) => [
        for (final slot in slots)
          _slot(
            context,
            size,
            slot,
            _entryFor(slot, legacyFlat442),
            finishedBenchCounts,
            legacyFlat442,
          ),
      ],
    );
  }

  Widget _slot(
    BuildContext context,
    Size size,
    FootballFormationSlot slot,
    MatchCompositionEntry? entry,
    Map<String, int> finishedBenchCounts,
    bool legacyFlat442,
  ) {
    // Mêmes vignettes que partout ailleurs : le maillot vient du terrain
    // partagé. Elles suivent la largeur du terrain, qui se réduit quand le
    // banc s'affiche à côté, pour rester lisibles sans se chevaucher.
    final metrics =
        markerMetrics ?? FormationMarkerMetrics.forPitch(size.width);
    final pitch = metrics.pitch;
    final width = metrics.width;
    final height = metrics.height;
    final diameter = metrics.avatarSize;

    // Les coordonnées historiques de l'ancien 4-4-2 étaient très tassées
    // vers le bas. On conserve les données brutes mais on les rééquilibre
    // visuellement. Toutes les autres compositions gardent leurs coordonnées.
    final visualPosition = entry == null
        ? slot.position
        : _displayPosition(entry, legacyFlat442: legacyFlat442);
    final x = visualPosition.dx.clamp(0.08, 0.92).toDouble();
    final y = visualPosition.dy.clamp(0.06, 0.94).toDouble();
    final left =
        (x * size.width - width / 2).clamp(0.0, size.width - width).toDouble();
    final top = (y * size.height - height / 2)
        .clamp(0.0, size.height - height)
        .toDouble();

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: DragTarget<MatchCompositionEntry>(
        onWillAcceptWithDetails: (details) =>
            editable && details.data.canBeSelected,
        onAcceptWithDetails: (details) => onDroppedOnSlot(details.data, slot),
        builder: (context, candidates, rejected) {
          final highlighted = candidates.isNotEmpty;
          if (entry == null) {
            return Align(
              alignment: Alignment.topCenter,
              child: GrintaPitchEmptySlot(
                metrics: pitch,
                positionLabel: slot.label,
                highlighted: highlighted,
              ),
            );
          }

          final finishedBenchCount =
              finishedBenchCounts[entry.participantId] ?? 0;
          final marker = Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: editable ? () => onRemoveFromField(entry) : null,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: width,
                    height: diameter,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        GrintaPitchJersey(
                          diameter: diameter,
                          label: CompositionPlayerTile.initialsOf(
                            entry.displayName,
                          ),
                          highlighted: entry.isGoalkeeper || highlighted,
                          photo: (entry.photoUrl?.trim().isNotEmpty ?? false)
                              ? PlayerAvatar(
                                  photoUrl: entry.photoUrl,
                                  name: entry.displayName,
                                  isGoalkeeper: entry.isGoalkeeper,
                                  size: diameter,
                                  fallbackScale: 1,
                                )
                              : null,
                        ),
                        if (finishedBenchCount > 0)
                          Positioned(
                            right: (width - diameter) / 2 - diameter * .18,
                            top: -2,
                            child: SubstituteHistoryBadge(
                              count: finishedBenchCount,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Le nom repose sur une plaque sombre : posé à même le
                  // vert, il se perdait dès que la pelouse s'éclaircissait.
                  GrintaPitchNamePlate(
                    name: entry.displayName.trim(),
                    fontSize: pitch.nameFontSize,
                  ),
                ],
              ),
            ),
          );
          if (!editable) return marker;
          final autoScroll = DragAutoScroller(context);
          return LongPressDraggable<MatchCompositionEntry>(
            data: entry,
            feedback: Material(
              type: MaterialType.transparency,
              child: SizedBox(width: width, height: height, child: marker),
            ),
            childWhenDragging: Opacity(opacity: .25, child: marker),
            onDragUpdate: (details) =>
                autoScroll.update(details.globalPosition),
            onDragEnd: (_) => autoScroll.stop(),
            onDraggableCanceled: (_, __) => autoScroll.stop(),
            child: marker,
          );
        },
      ),
    );
  }
}
