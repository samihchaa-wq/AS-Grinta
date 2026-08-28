import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/drag_auto_scroll.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/football_pitch.dart';
import 'package:flutter/material.dart';

/// Relie le terrain aux vignettes de joueurs affichées en dehors du terrain
/// (banc pré-match, banc du Live). Un seul terrain éditable est actif à la
/// fois dans l'application ; le propriétaire permet d'éviter qu'un ancien
/// écran conserve une sélection après sa destruction.
class FormationPitchTapSelection {
  FormationPitchTapSelection._();

  static Object? _owner;
  static bool Function(MatchCompositionEntry entry)? _placePlayer;

  static bool get hasSelection => _placePlayer != null;

  static void activate({
    required Object owner,
    required bool Function(MatchCompositionEntry entry) placePlayer,
  }) {
    _owner = owner;
    _placePlayer = placePlayer;
  }

  static bool placePlayer(MatchCompositionEntry entry) {
    return _placePlayer?.call(entry) ?? false;
  }

  static void clear(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _placePlayer = null;
  }
}

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
class FormationMarkerMetrics {
  const FormationMarkerMetrics(this.width);

  /// Taille des marqueurs pour un terrain large de [pitchWidth].
  factory FormationMarkerMetrics.forPitch(double pitchWidth) =>
      FormationMarkerMetrics((pitchWidth / 5.6).clamp(44.0, 64.0).toDouble());

  final double width;

  double get height => width * 1.32;

  double get avatarSize => width * .82;

  double get nameFontSize => (width * .18).clamp(10.5, 12.5).toDouble();

  /// Largeur maximale de l'étiquette du prénom.
  ///
  /// Elle déborde volontairement du marqueur : à la largeur de la photo, un
  /// prénom comme « François » était coupé en « Franç… » dès que le terrain se
  /// resserrait pour laisser la place au banc. L'étiquette est centrée sous la
  /// photo et le débordement va dans l'espace vide du terrain, jamais sur le
  /// visage du joueur voisin.
  double get nameMaxWidth => width * 1.6;

  /// Hauteur réservée à l'étiquette dans le marqueur : la hauteur naturelle
  /// de la pastille, avec un peu de marge pour les prénoms accentués
  /// (« François ») qui descendent sous la ligne de base.
  double get nameHeight => nameFontSize * 1.35 + 2;
}

class FormationPitchEditor extends StatefulWidget {
  const FormationPitchEditor({
    super.key,
    required this.slots,
    required this.entries,
    required this.onDroppedOnSlot,
    required this.onRemoveFromField,
    this.editable = true,
    this.finishedBenchCounts = const {},
    this.markerMetrics,
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

  @override
  State<FormationPitchEditor> createState() => _FormationPitchEditorState();
}

class _FormationPitchEditorState extends State<FormationPitchEditor> {
  FootballFormationSlot? _selectedSlot;

  bool _sameSlot(FootballFormationSlot a, FootballFormationSlot b) =>
      a.label == b.label && (a.position - b.position).distance < .001;

  bool _isSelected(FootballFormationSlot slot) {
    final selected = _selectedSlot;
    return selected != null && _sameSlot(selected, slot);
  }

  @override
  void didUpdateWidget(covariant FormationPitchEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = _selectedSlot;
    if (!widget.editable ||
        (selected != null &&
            !widget.slots.any((slot) => _sameSlot(slot, selected)))) {
      _clearSelection();
    }
  }

  @override
  void dispose() {
    FormationPitchTapSelection.clear(this);
    super.dispose();
  }

  void _selectSlot(FootballFormationSlot slot) {
    if (!widget.editable) return;
    if (_isSelected(slot)) {
      _clearSelection();
      return;
    }
    setState(() => _selectedSlot = slot);
    FormationPitchTapSelection.activate(
      owner: this,
      placePlayer: _placeSelectedPlayer,
    );
  }

  void _clearSelection() {
    FormationPitchTapSelection.clear(this);
    if (!mounted || _selectedSlot == null) return;
    setState(() => _selectedSlot = null);
  }

  bool _placeSelectedPlayer(MatchCompositionEntry entry) {
    final target = _selectedSlot;
    if (!mounted ||
        !widget.editable ||
        target == null ||
        !entry.canBeSelected) {
      return false;
    }
    _clearSelection();
    widget.onDroppedOnSlot(entry, target);
    return true;
  }

  void _tapOccupiedSlot(
    FootballFormationSlot slot,
    MatchCompositionEntry entry,
  ) {
    if (!widget.editable) return;
    final selected = _selectedSlot;
    if (selected == null) {
      _selectSlot(slot);
      return;
    }
    if (_sameSlot(selected, slot)) {
      _clearSelection();
      return;
    }
    _placeSelectedPlayer(entry);
  }

  MatchCompositionEntry? _entryFor(
    FootballFormationSlot slot,
    bool legacyFlat442,
  ) {
    MatchCompositionEntry? closest;
    var distance = double.infinity;
    for (final entry in widget.entries) {
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
      child: AspectRatio(
        aspectRatio: .68,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final legacyFlat442 = _usesLegacyFlat442Layout(widget.entries);
            return DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF124529),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFF6DAD8B), width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 18,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: CustomPaint(painter: FootballPitchPainter()),
                    ),
                    for (final slot in widget.slots)
                      _slot(
                        context,
                        constraints.biggest,
                        slot,
                        _entryFor(slot, legacyFlat442),
                        widget.finishedBenchCounts,
                        legacyFlat442,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
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
    // Mêmes proportions que la composition d'un match terminé
    // (CompositionPitch) : photo généreuse, prénom juste dessous. Les
    // marqueurs suivent la largeur du terrain, qui se réduit quand le banc
    // s'affiche à côté, pour rester lisibles sans se chevaucher.
    final metrics =
        widget.markerMetrics ?? FormationMarkerMetrics.forPitch(size.width);
    final width = metrics.width;
    final height = metrics.height;
    final avatarSize = metrics.avatarSize;
    final nameFontSize = metrics.nameFontSize;

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
            widget.editable && details.data.canBeSelected,
        onAcceptWithDetails: (details) {
          _clearSelection();
          widget.onDroppedOnSlot(details.data, slot);
        },
        builder: (context, candidates, rejected) {
          final selected = _isSelected(slot);
          final highlighted = candidates.isNotEmpty || selected;
          if (entry == null) {
            // L'emplacement vide reste carré, à la taille de la photo, pour
            // que la grille des postes garde son alignement.
            return Align(
              alignment: Alignment.topCenter,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.editable ? () => _selectSlot(slot) : null,
                  borderRadius: BorderRadius.circular(17),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: avatarSize,
                    height: avatarSize,
                    decoration: BoxDecoration(
                      color: highlighted
                          ? AppTheme.accent.withValues(alpha: .32)
                          : Colors.white.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: highlighted ? AppTheme.accent : Colors.white54,
                        width: highlighted ? 2.5 : 1,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: AppTheme.accent.withValues(alpha: .8),
                                blurRadius: 9,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          selected ? Icons.ads_click_rounded : Icons.add,
                          color: Colors.white,
                          size: 18,
                        ),
                        Text(
                          slot.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          final finishedBenchCount =
              finishedBenchCounts[entry.participantId] ?? 0;
          final marker = Material(
            color: Colors.transparent,
            child: InkWell(
              onTap:
                  widget.editable ? () => _tapOccupiedSlot(slot, entry) : null,
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.accent.withValues(alpha: .12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: highlighted ? AppTheme.accent : Colors.transparent,
                    width: highlighted ? 2.5 : 0,
                  ),
                  boxShadow: highlighted
                      ? [
                          BoxShadow(
                            color: AppTheme.accent.withValues(alpha: .9),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
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
                          size: avatarSize,
                        ),
                        if (finishedBenchCount > 0)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: SubstituteHistoryBadge(
                              count: finishedBenchCount,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Prénom sur fond translucide sous la photo, comme sur
                    // la composition d'un match terminé : jamais posé sur le
                    // visage, et lisible même par-dessus les tracés blancs
                    // du terrain. L'étiquette a le droit d'être plus large que
                    // le marqueur pour ne pas tronquer les prénoms longs.
                    SizedBox(
                      width: width,
                      height: metrics.nameHeight,
                      child: OverflowBox(
                        minWidth: 0,
                        maxWidth: metrics.nameMaxWidth,
                        minHeight: 0,
                        maxHeight: double.infinity,
                        alignment: Alignment.topCenter,
                        child: PitchPlayerName(
                          label: entry.displayName.trim(),
                          fontSize: nameFontSize,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          if (!widget.editable) return marker;
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
