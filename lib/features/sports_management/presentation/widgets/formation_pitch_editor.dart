import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/composition_drag.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/formation_slot_assignment.dart';
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
}

/// Ce que le terrain fera d'un joueur relâché sur un poste donné.
class FormationDrop {
  const FormationDrop({
    required this.entry,
    required this.slot,
    required this.occupant,
  });

  /// Le joueur déplacé.
  final MatchCompositionEntry entry;

  /// Le poste visé (le plus proche du point relâché).
  final FootballFormationSlot slot;

  /// Le joueur affiché sur ce poste au moment du dépôt, s'il y en avait un.
  ///
  /// Les écrans appelants l'utilisaient jusqu'ici en recalculant « le premier
  /// joueur à moins de 0,12 du poste », un critère différent de celui de
  /// l'affichage : l'échange pouvait porter sur un autre joueur que celui
  /// qu'on voyait. Le terrain le fournit désormais lui-même.
  final MatchCompositionEntry? occupant;
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
  final ValueChanged<FormationDrop> onDroppedOnSlot;
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
  /// Clé posée sur la pile qui contient les marqueurs : c'est elle, et non le
  /// cadre extérieur, qui définit le repère des coordonnées normalisées.
  final _pitchKey = GlobalKey();

  /// Poste survolé pendant un glisser. Un `ValueNotifier` plutôt qu'un
  /// `setState` : seuls les marqueurs se redessinent, pas tout le terrain, à
  /// chaque pixel parcouru par le doigt.
  final _hoveredSlot = ValueNotifier<int?>(null);

  FootballFormationSlot? _selectedSlot;

  /// Dernière répartition postes → joueurs calculée à l'affichage. Les
  /// dépôts et les appuis s'y réfèrent pour désigner exactement le joueur que
  /// l'utilisateur voit sur le poste.
  Map<int, MatchCompositionEntry> _slotEntries = const {};

  /// Point réellement occupé par chaque poste à l'écran : la position du
  /// joueur qui s'y trouve, ou celle du poste s'il est vide. C'est ce point,
  /// et non la position théorique du poste, qui sert à désigner la cible d'un
  /// dépôt — sinon la vignette mise en évidence n'aurait pas été celle sur
  /// laquelle on relâche.
  List<Offset> _slotAnchors = const [];

  bool _sameSlot(FootballFormationSlot a, FootballFormationSlot b) =>
      a.label == b.label && (a.position - b.position).distance < .001;

  bool _isSelected(FootballFormationSlot slot) {
    final selected = _selectedSlot;
    return selected != null && _sameSlot(selected, slot);
  }

  int? _indexOfSlot(FootballFormationSlot slot) {
    for (var index = 0; index < widget.slots.length; index += 1) {
      if (_sameSlot(widget.slots[index], slot)) return index;
    }
    return null;
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
    _hoveredSlot.dispose();
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
    final index = _indexOfSlot(target);
    _clearSelection();
    _notifyDrop(entry, target, index);
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

  void _notifyDrop(
    MatchCompositionEntry entry,
    FootballFormationSlot slot,
    int? slotIndex,
  ) {
    final occupant = slotIndex == null ? null : _slotEntries[slotIndex];
    widget.onDroppedOnSlot(
      FormationDrop(
        entry: entry,
        slot: slot,
        occupant:
            occupant?.participantId == entry.participantId ? null : occupant,
      ),
    );
  }

  /// Le poste le plus proche du point relâché.
  ///
  /// Auparavant chaque poste portait sa propre zone de dépôt, à peine plus
  /// grande que la photo : entre deux postes, un joueur relâché ne tombait
  /// nulle part et rien ne se passait. Tout le terrain accepte désormais le
  /// dépôt et le ramène au poste le plus proche.
  int? _slotIndexAt(Offset globalPointer) {
    if (widget.slots.isEmpty) return null;
    final renderObject = _pitchKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final size = renderObject.size;
    if (size.isEmpty) return null;
    final local = renderObject.globalToLocal(globalPointer);
    final normalized = Offset(local.dx / size.width, local.dy / size.height);
    return nearestSlotIndex(_slotAnchors, normalized);
  }

  void _updateHover(Offset globalPointer) {
    _hoveredSlot.value = _slotIndexAt(globalPointer);
  }

  void _acceptDrop(DragTargetDetails<MatchCompositionEntry> details) {
    _hoveredSlot.value = null;
    _clearSelection();
    final pointer = CompositionDragPointer.resolve(details.offset);
    final index = _slotIndexAt(pointer);
    if (index == null) return;
    _notifyDrop(details.data, widget.slots[index], index);
  }

  @override
  Widget build(BuildContext context) {
    final legacyFlat442 = _usesLegacyFlat442Layout(widget.entries);
    final positions = [
      for (final entry in widget.entries)
        _displayPosition(entry, legacyFlat442: legacyFlat442),
    ];
    final assignment = assignEntriesToSlots(
      slotPositions: [for (final slot in widget.slots) slot.position],
      entryPositions: positions,
    );
    _slotEntries = {
      for (final pair in assignment.entries)
        pair.key: widget.entries[pair.value],
    };
    _slotAnchors = [
      for (var index = 0; index < widget.slots.length; index += 1)
        if (assignment[index] case final entryIndex?)
          positions[entryIndex]
        else
          widget.slots[index].position,
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
      child: AspectRatio(
        aspectRatio: kPitchAspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return DragTarget<MatchCompositionEntry>(
              onWillAcceptWithDetails: (details) =>
                  widget.editable && details.data.canBeSelected,
              onMove: (details) => _updateHover(
                CompositionDragPointer.resolve(details.offset),
              ),
              onLeave: (_) => _hoveredSlot.value = null,
              onAcceptWithDetails: _acceptDrop,
              builder: (context, candidates, rejected) {
                final hovering = candidates.isNotEmpty;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  decoration: BoxDecoration(
                    color: const Color(0xFF124529),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color:
                          hovering ? AppTheme.accent : const Color(0xFF6DAD8B),
                      width: 1.5,
                    ),
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
                      key: _pitchKey,
                      children: [
                        const Positioned.fill(
                          child: CustomPaint(painter: FootballPitchPainter()),
                        ),
                        for (var index = 0;
                            index < widget.slots.length;
                            index += 1)
                          _slot(
                            context,
                            constraints.biggest,
                            index,
                            positions,
                            legacyFlat442,
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _slot(
    BuildContext context,
    Size size,
    int index,
    List<Offset> positions,
    bool legacyFlat442,
  ) {
    final slot = widget.slots[index];
    final entry = _slotEntries[index];

    // Mêmes proportions que la composition d'un match terminé
    // (CompositionPitch) : photo généreuse, prénom juste dessous. Les
    // marqueurs suivent la largeur du terrain, qui se réduit quand le banc
    // s'affiche à côté, pour rester lisibles sans se chevaucher.
    final metrics =
        widget.markerMetrics ?? FormationMarkerMetrics.forPitch(size.width);
    final width = metrics.width;
    final height = metrics.height;

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
      child: ValueListenableBuilder<int?>(
        valueListenable: _hoveredSlot,
        builder: (context, hovered, _) {
          final selected = _isSelected(slot);
          final targeted = hovered == index;
          return entry == null
              ? _emptySlot(slot, metrics,
                  targeted: targeted, selected: selected)
              : _occupiedSlot(
                  slot,
                  entry,
                  metrics,
                  targeted: targeted,
                  selected: selected,
                );
        },
      ),
    );
  }

  Widget _emptySlot(
    FootballFormationSlot slot,
    FormationMarkerMetrics metrics, {
    required bool targeted,
    required bool selected,
  }) {
    final highlighted = targeted || selected;
    // L'emplacement vide reste carré, à la taille de la photo, pour que la
    // grille des postes garde son alignement.
    return Align(
      alignment: Alignment.topCenter,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.editable ? () => _selectSlot(slot) : null,
          borderRadius: BorderRadius.circular(17),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: metrics.avatarSize,
            height: metrics.avatarSize,
            decoration: BoxDecoration(
              color: highlighted
                  ? AppTheme.accent.withValues(alpha: .32)
                  : Colors.white.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: highlighted ? AppTheme.accent : Colors.white54,
                width: highlighted ? 2.5 : 1,
              ),
              boxShadow: highlighted
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
                  targeted
                      ? Icons.south_rounded
                      : selected
                          ? Icons.ads_click_rounded
                          : Icons.add,
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

  Widget _occupiedSlot(
    FootballFormationSlot slot,
    MatchCompositionEntry entry,
    FormationMarkerMetrics metrics, {
    required bool targeted,
    required bool selected,
  }) {
    final highlighted = targeted || selected;
    final finishedBenchCount =
        widget.finishedBenchCounts[entry.participantId] ?? 0;

    final marker = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.editable ? () => _tapOccupiedSlot(slot, entry) : null,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
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
                    size: metrics.avatarSize,
                  ),
                  if (finishedBenchCount > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: SubstituteHistoryBadge(
                        count: finishedBenchCount,
                      ),
                    ),
                  // Pendant un glisser, le poste visé annonce clairement
                  // qu'un dépôt ici échangera les deux joueurs.
                  if (targeted)
                    Positioned.fill(
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppTheme.accent,
                            shape: BoxShape.circle,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(3),
                            child: Icon(
                              Icons.swap_horiz_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              // Prénom sur fond translucide sous la photo, comme sur la
              // composition d'un match terminé : jamais posé sur le visage,
              // et lisible même par-dessus les tracés blancs du terrain.
              PitchPlayerName(
                label: entry.displayName.trim(),
                fontSize: metrics.nameFontSize,
              ),
            ],
          ),
        ),
      ),
    );

    if (!widget.editable) return marker;
    return CompositionDraggable<MatchCompositionEntry>(
      data: entry,
      childWhenDragging: Opacity(opacity: .25, child: marker),
      feedback: SizedBox(
        width: metrics.width,
        height: metrics.height,
        child: marker,
      ),
      feedbackLift: metrics.height * .45,
      onDragEnd: () => _hoveredSlot.value = null,
      child: marker,
    );
  }
}
