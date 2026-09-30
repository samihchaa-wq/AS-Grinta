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
  static bool Function(MatchCompositionEntry entry)? _tapPlayer;
  static bool _hasSelection = false;
  static final ValueNotifier<String?> _selectedParticipantId =
      ValueNotifier<String?>(null);

  static bool get hasSelection => _hasSelection;

  /// Joueur du banc actuellement sélectionné au clic, s'il y en a un.
  ///
  /// Les vignettes hors terrain s'abonnent à cette valeur pour afficher la
  /// même surbrillance persistante que les titulaires sélectionnés.
  static ValueNotifier<String?> get selectedParticipantId =>
      _selectedParticipantId;

  /// Branche le banc sur le terrain éditable actif.
  ///
  /// Le callback reste actif même sans emplacement déjà sélectionné : un clic
  /// sur un remplaçant peut ainsi devenir le premier clic du remplacement.
  static void activate({
    required Object owner,
    required bool Function(MatchCompositionEntry entry) placePlayer,
  }) {
    _owner = owner;
    _tapPlayer = placePlayer;
  }

  static bool placePlayer(MatchCompositionEntry entry) {
    return _tapPlayer?.call(entry) ?? false;
  }

  static void updateSelection({
    required Object owner,
    required bool hasSelection,
    String? selectedParticipantId,
  }) {
    if (!identical(_owner, owner)) return;
    _hasSelection = hasSelection;
    if (_selectedParticipantId.value != selectedParticipantId) {
      _selectedParticipantId.value = selectedParticipantId;
    }
  }

  static void clear(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _tapPlayer = null;
    _hasSelection = false;
    if (_selectedParticipantId.value != null) {
      _selectedParticipantId.value = null;
    }
  }
}

/// Surbrillance persistante d'un joueur du banc sélectionné au clic.
/// Joueur sélectionné (appui ou glisser) : un jaune doré plus foncé que le
/// jaune du club, pour que le prénom blanc reste lisible.
const formationSelectionColor = Color(0xFFB39500);

class FormationPitchTapSelectionHighlight extends StatelessWidget {
  const FormationPitchTapSelectionHighlight({
    super.key,
    required this.entry,
    required this.child,
  });

  final MatchCompositionEntry entry;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: FormationPitchTapSelection.selectedParticipantId,
      child: child,
      builder: (context, selectedParticipantId, child) {
        final selected = selectedParticipantId == entry.participantId;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: selected
                ? formationSelectionColor.withValues(alpha: .22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? formationSelectionColor : Colors.transparent,
              width: selected ? 2.5 : 0,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: formationSelectionColor.withValues(alpha: .35),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
    );
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
    this.benchLabels = const {},
    this.benchColors = const {},
    this.namesOnly = false,
    this.nameColors = const {},
    this.nameSuffixes = const {},
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

  /// Texte affiché à la place du compteur, par participantId (« 2.1 » en
  /// direct). Un joueur absent garde son simple compteur.
  final Map<String, String> benchLabels;

  /// Couleur de la pastille, par participantId (salve de la dernière sortie).
  final Map<String, Color> benchColors;

  /// Affiche seulement le prénom de chaque joueur, sans pastille d'initiales
  /// ni photo (en direct).
  final bool namesOnly;

  /// Couleur du prénom, par participantId (prochains à sortir, en direct).
  final Map<String, Color> nameColors;

  /// Texte après le prénom, par participantId (temps de jeu en direct).
  final Map<String, String> nameSuffixes;

  /// Taille imposée des marqueurs. Renseignée quand un autre bloc (le banc du
  /// Tableau Blanc) doit afficher exactement les mêmes vignettes ; sinon elle
  /// est déduite de la largeur réelle du terrain.
  final FormationMarkerMetrics? markerMetrics;

  @override
  State<FormationPitchEditor> createState() => _FormationPitchEditorState();
}

class _FormationPitchEditorState extends State<FormationPitchEditor> {
  FootballFormationSlot? _selectedSlot;
  MatchCompositionEntry? _selectedBenchPlayer;

  bool _sameSlot(FootballFormationSlot a, FootballFormationSlot b) =>
      a.label == b.label && (a.position - b.position).distance < .001;

  bool _isSelected(FootballFormationSlot slot) {
    final selected = _selectedSlot;
    return selected != null && _sameSlot(selected, slot);
  }

  @override
  void initState() {
    super.initState();
    if (widget.editable) _activateTapSelection();
  }

  @override
  void didUpdateWidget(covariant FormationPitchEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = _selectedSlot;
    if (!widget.editable) {
      _clearSelection(detach: true);
      return;
    }
    _activateTapSelection();
    if (selected != null &&
        !widget.slots.any((slot) => _sameSlot(slot, selected))) {
      _clearSelection();
    }
  }

  @override
  void dispose() {
    FormationPitchTapSelection.clear(this);
    super.dispose();
  }

  void _activateTapSelection() {
    FormationPitchTapSelection.activate(
      owner: this,
      placePlayer: _tapBenchPlayer,
    );
    _syncTapSelectionState();
  }

  void _syncTapSelectionState() {
    FormationPitchTapSelection.updateSelection(
      owner: this,
      hasSelection: _selectedSlot != null || _selectedBenchPlayer != null,
      selectedParticipantId: _selectedBenchPlayer?.participantId,
    );
  }

  void _selectSlot(FootballFormationSlot slot) {
    if (!widget.editable) return;
    if (_isSelected(slot)) {
      _clearSelection();
      return;
    }
    setState(() {
      _selectedSlot = slot;
      _selectedBenchPlayer = null;
    });
    _syncTapSelectionState();
  }

  void _clearSelection({bool detach = false}) {
    final hadSelection = _selectedSlot != null || _selectedBenchPlayer != null;
    _selectedSlot = null;
    _selectedBenchPlayer = null;
    if (detach) {
      FormationPitchTapSelection.clear(this);
    } else {
      _syncTapSelectionState();
    }
    if (hadSelection && mounted) setState(() {});
  }

  bool _tapBenchPlayer(MatchCompositionEntry entry) {
    if (!mounted || !widget.editable || !entry.canBeSelected) return false;

    final target = _selectedSlot;
    if (target != null) {
      _clearSelection();
      widget.onDroppedOnSlot(entry, target);
      return true;
    }

    if (_selectedBenchPlayer?.participantId == entry.participantId) {
      _clearSelection();
      return true;
    }

    setState(() {
      _selectedSlot = null;
      _selectedBenchPlayer = entry;
    });
    _syncTapSelectionState();
    return true;
  }

  bool _placeSelectedBenchPlayer(FootballFormationSlot slot) {
    final selectedBenchPlayer = _selectedBenchPlayer;
    if (selectedBenchPlayer == null) return false;
    _clearSelection();
    widget.onDroppedOnSlot(selectedBenchPlayer, slot);
    return true;
  }

  void _tapEmptySlot(FootballFormationSlot slot) {
    if (!widget.editable) return;
    if (_placeSelectedBenchPlayer(slot)) return;
    _selectSlot(slot);
  }

  void _tapOccupiedSlot(
    FootballFormationSlot slot,
    MatchCompositionEntry entry,
  ) {
    if (!widget.editable) return;
    if (_placeSelectedBenchPlayer(slot)) return;

    final selected = _selectedSlot;
    if (selected == null) {
      _selectSlot(slot);
      return;
    }
    if (_sameSlot(selected, slot)) {
      _clearSelection();
      return;
    }

    _clearSelection();
    widget.onDroppedOnSlot(entry, selected);
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
    if (distance < .12) return closest;

    // Compatibilité : les nouveaux gabarits peuvent déplacer un poste alors
    // qu'une composition enregistrée conserve encore ses anciennes
    // coordonnées. Dans ce cas seulement, slot_label permet de retrouver le
    // joueur au lieu de le faire disparaître du terrain.
    for (final entry in widget.entries) {
      if (entry.slotLabel == slot.label) return entry;
    }
    return null;
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
    // visuellement. Toutes les autres compositions gardent leurs coordonnées,
    // sauf si le poste n'était plus détectable par proximité.
    final storedPosition = entry == null
        ? slot.position
        : _displayPosition(entry, legacyFlat442: legacyFlat442);
    final staleCanonicalPosition = entry != null &&
        entry.slotLabel == slot.label &&
        (storedPosition - slot.position).distance >= .12;
    final visualPosition =
        staleCanonicalPosition ? slot.position : storedPosition;
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
                  onTap: widget.editable ? () => _tapEmptySlot(slot) : null,
                  borderRadius: BorderRadius.circular(17),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: avatarSize,
                    height: avatarSize,
                    decoration: BoxDecoration(
                      color: highlighted
                          ? formationSelectionColor.withValues(alpha: .32)
                          : Colors.white.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: highlighted
                            ? formationSelectionColor
                            : Colors.white54,
                        width: highlighted ? 2.5 : 1,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: formationSelectionColor.withValues(
                                    alpha: .8),
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
                            fontWeight: FontWeight.w400,
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
          final benchLabel = widget.benchLabels[entry.participantId];
          final marker = Material(
            color: Colors.transparent,
            child: InkWell(
              onTap:
                  widget.editable ? () => _tapOccupiedSlot(slot, entry) : null,
              borderRadius: BorderRadius.circular(16),
              // Prénoms seuls : pas d'effet de toucher sur toute la place du
              // joueur, le cadre de sélection suffit.
              splashColor: widget.namesOnly ? Colors.transparent : null,
              highlightColor: widget.namesOnly ? Colors.transparent : null,
              hoverColor: widget.namesOnly ? Colors.transparent : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                // Prénoms seuls : le cadre de sélection épouse le prénom
                // (voir _nameOnlyMarker) au lieu de toute la place du joueur.
                decoration: _selectionDecoration(
                  selected: selected && !widget.namesOnly,
                  highlighted: highlighted && !widget.namesOnly,
                ),
                child: widget.namesOnly
                    ? _nameOnlyMarker(
                        entry: entry,
                        selected: selected,
                        highlighted: highlighted,
                        width: width,
                        height: avatarSize + 2 + metrics.nameHeight,
                        fontSize: nameFontSize,
                        badge: finishedBenchCount > 0
                            ? SubstituteHistoryBadge(
                                count: finishedBenchCount,
                                label: benchLabel,
                                color: widget.benchColors[entry.participantId],
                              )
                            : null,
                      )
                    : Column(
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
                                size: avatarSize,
                              ),
                              if (finishedBenchCount > 0)
                                Positioned(
                                  right: -2,
                                  top: -2,
                                  child: SubstituteHistoryBadge(
                                    count: finishedBenchCount,
                                    label: benchLabel,
                                    color:
                                        widget.benchColors[entry.participantId],
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

  /// Marqueur du mode prénoms seuls : le prénom à la place qu'il occupait
  /// sous la pastille (même encombrement, pour ne rien décaler), et
  /// le repère « passage.série » juste dessous : au-dessus ou à côté, il
  /// serait coupé pour les joueurs placés en bord de terrain.
  BoxDecoration _selectionDecoration({
    required bool selected,
    required bool highlighted,
  }) =>
      BoxDecoration(
        color: selected
            ? formationSelectionColor.withValues(alpha: .22)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted ? formationSelectionColor : Colors.transparent,
          width: highlighted ? 2.5 : 0,
        ),
        boxShadow: highlighted
            ? [
                BoxShadow(
                  color: formationSelectionColor.withValues(alpha: .35),
                  blurRadius: 6,
                ),
              ]
            : null,
      );

  Widget _nameOnlyMarker({
    required MatchCompositionEntry entry,
    bool selected = false,
    bool highlighted = false,
    required double width,
    required double height,
    required double fontSize,
    required Widget? badge,
  }) {
    final color = widget.nameColors[entry.participantId];
    return SizedBox(
      width: width,
      height: height,
      child: OverflowBox(
        minWidth: 0,
        maxWidth: FormationMarkerMetrics(width).nameMaxWidth,
        maxHeight: double.infinity,
        // Sur les côtés du terrain, l'étiquette se cale vers l'intérieur
        // pour ne pas être coupée par le bord.
        alignment: switch (entry.x ?? .5) {
          < .2 => Alignment.topLeft,
          > .8 => Alignment.topRight,
          _ => Alignment.topCenter,
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Le prénom reste exactement où il était sous la pastille : la
            // place du joueur sur le terrain ne bouge pas.
            SizedBox(
              height: height - FormationMarkerMetrics(width).nameHeight - 4,
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.all(4),
              decoration: _selectionDecoration(
                selected: selected,
                highlighted: highlighted,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PitchPlayerName(
                    label: entry.displayName.trim(),
                    fontSize: fontSize * 1.15,
                    color: color ?? Colors.white,
                    fontWeight: FontWeight.w400,
                    suffix: widget.nameSuffixes[entry.participantId],
                  ),
                  if (badge != null) badge,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
