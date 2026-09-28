import 'package:as_grinta/core/storage/profile_photo_urls.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/name_validation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/football_pitch.dart';
import 'package:flutter/material.dart';

class CompositionPitch extends StatefulWidget {
  const CompositionPitch({
    super.key,
    required this.entries,
    this.editable = false,
    this.onMoved,
    this.onPlayerTap,
  });

  final List<MatchCompositionEntry> entries;
  final bool editable;
  final void Function(
    MatchCompositionEntry entry,
    MatchCompositionZone zone,
    Offset? normalizedPosition,
  )? onMoved;
  final ValueChanged<MatchCompositionEntry>? onPlayerTap;

  @override
  State<CompositionPitch> createState() => _CompositionPitchState();
}

class _CompositionPitchState extends State<CompositionPitch> {
  final _fieldKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
      child: AspectRatio(
        aspectRatio: 0.68,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return DragTarget<MatchCompositionEntry>(
              onWillAcceptWithDetails: (details) =>
                  widget.editable && details.data.canBeSelected,
              onAcceptWithDetails: _acceptOnField,
              builder: (context, candidates, rejected) {
                final highlighted = candidates.isNotEmpty;
                return AnimatedContainer(
                  key: _fieldKey,
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: const Color(0xFF124529),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: highlighted
                          ? AppTheme.accent
                          : const Color(0xFF6DAD8B),
                      width: highlighted ? 3 : 1.5,
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
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: FootballPitchPainter(
                              highlighted: highlighted,
                            ),
                          ),
                        ),
                        for (final entry in widget.entries)
                          _positionedPlayer(
                            context,
                            entry,
                            constraints.biggest,
                          ),
                        if (widget.editable && widget.entries.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Glisse un joueur ici ou utilise son menu.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
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

  Widget _positionedPlayer(
    BuildContext context,
    MatchCompositionEntry entry,
    Size size,
  ) {
    const markerWidth = 64.0;
    const markerHeight = 84.0;
    final x = (entry.x ?? 0.5).clamp(0.08, 0.92).toDouble();
    final y = (entry.y ?? 0.5).clamp(0.06, 0.94).toDouble();
    final left = (x * size.width - markerWidth / 2)
        .clamp(0.0, size.width - markerWidth)
        .toDouble();
    final top = (y * size.height - markerHeight / 2)
        .clamp(0.0, size.height - markerHeight)
        .toDouble();

    final marker = CompositionPlayerTile(
      entry: entry,
      onTap:
          widget.onPlayerTap == null ? null : () => widget.onPlayerTap!(entry),
    );

    return Positioned(
      left: left,
      top: top,
      width: markerWidth,
      height: markerHeight,
      child: widget.editable && entry.canBeSelected
          ? LongPressDraggable<MatchCompositionEntry>(
              data: entry,
              feedback: Material(
                type: MaterialType.transparency,
                child: SizedBox(
                  width: markerWidth,
                  height: markerHeight,
                  child: marker,
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.28, child: marker),
              child: marker,
            )
          : marker,
    );
  }

  void _acceptOnField(DragTargetDetails<MatchCompositionEntry> details) {
    final renderObject = _fieldKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final local = renderObject.globalToLocal(details.offset);
    final normalized = Offset(
      (local.dx / renderObject.size.width).clamp(0.08, 0.92).toDouble(),
      (local.dy / renderObject.size.height).clamp(0.06, 0.94).toDouble(),
    );
    widget.onMoved?.call(details.data, MatchCompositionZone.field, normalized);
  }
}

/// Nombre de colonnes du banc compact.
///
/// Le terrain garde exactement la même largeur quel que soit le nombre de
/// remplaçants : seule l'organisation interne de la zone de gauche change.
int compositionBenchColumnCount(int count) {
  if (count <= 0) return 0;
  if (count <= 6) return 1;
  if (count <= 12) return 2;
  return 3;
}

/// Terrain compact avec le banc à gauche.
///
/// La largeur réservée au banc dépend uniquement de la largeur disponible,
/// jamais du nombre de remplaçants. Passer de 7 à 6 joueurs ne déplace donc
/// pas le terrain. Jusqu'à 15 joueurs (et au-delà), le banc se réorganise en
/// une, deux ou trois colonnes sans réduire toute la composition.
class CompositionPitchWithBench extends StatelessWidget {
  const CompositionPitchWithBench({
    super.key,
    required this.field,
    required this.bench,
    this.maxWidth = 520,
  });

  final List<MatchCompositionEntry> field;
  final List<MatchCompositionEntry> bench;
  final double maxWidth;

  static const double _gap = 6;
  static const double _benchWidthFraction = .31;
  static const double _minBenchWidth = 96;
  static const double _maxBenchWidth = 132;

  @override
  Widget build(BuildContext context) {
    if (bench.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: CompositionPitch(entries: field),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth =
                constraints.maxWidth.isFinite ? constraints.maxWidth : maxWidth;
            final benchWidth = (availableWidth * _benchWidthFraction)
                .clamp(_minBenchWidth, _maxBenchWidth)
                .toDouble();
            final pitchWidth = availableWidth - benchWidth - _gap;
            final pitchHeight = pitchWidth / .68;

            return SizedBox(
              height: pitchHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: benchWidth,
                    height: pitchHeight,
                    child: _CompositionBenchGrid(entries: bench),
                  ),
                  const SizedBox(width: _gap),
                  SizedBox(
                    width: pitchWidth,
                    child: CompositionPitch(entries: field),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CompositionBenchGrid extends StatelessWidget {
  const _CompositionBenchGrid({required this.entries});

  final List<MatchCompositionEntry> entries;

  @override
  Widget build(BuildContext context) {
    final columns = compositionBenchColumnCount(entries.length);
    if (columns == 0) return const SizedBox.shrink();
    final rows = (entries.length + columns - 1) ~/ columns;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellHeight = constraints.maxHeight / rows;

        return Column(
          children: [
            for (var row = 0; row < rows; row++)
              SizedBox(
                height: cellHeight,
                child: Row(
                  children: [
                    for (var column = 0; column < columns; column++)
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final index = row * columns + column;
                            if (index >= entries.length) {
                              return const SizedBox.shrink();
                            }
                            return _CompositionBenchPlayerTile(
                              entry: entries[index],
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CompositionBenchPlayerTile extends StatelessWidget {
  const _CompositionBenchPlayerTile({required this.entry});

  final MatchCompositionEntry entry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Remplaçant ${entry.displayName}',
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            var avatarSize = constraints.maxWidth * .72;
            final maxFromHeight = constraints.maxHeight * .54;
            if (avatarSize > maxFromHeight) avatarSize = maxFromHeight;
            avatarSize = avatarSize.clamp(24.0, 44.0).toDouble();
            final fontSize =
                (constraints.maxWidth * .22).clamp(8.0, 10.0).toDouble();

            return Center(
              child: SizedBox(
                width: constraints.maxWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: avatarSize + 8,
                      height: avatarSize + 8,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          PlayerAvatar(
                            photoUrl: entry.photoUrl,
                            name: entry.displayName,
                            lastName: entry.lastInitial,
                            isGoalkeeper: entry.isGoalkeeper,
                            size: avatarSize,
                          ),
                          if (entry.isMotm)
                            const Positioned(
                              top: -4,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Text(
                                  '👑',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ),
                            ),
                          if (entry.goals > 0)
                            Positioned(
                              left: 0,
                              bottom: 0,
                              child: GoalBadge(goals: entry.goals),
                            ),
                          if (entry.assists > 0)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: AssistBadge(assists: entry.assists),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xD1071527),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 1,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              entry.displayName.trim(),
                              maxLines: 1,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: fontSize,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      ),
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
}

class CompositionPlayerChip extends StatelessWidget {
  const CompositionPlayerChip({
    super.key,
    required this.entry,
    this.editable = false,
    this.onTap,
  });

  final MatchCompositionEntry entry;
  final bool editable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = ActionChip(
      avatar: PlayerAvatar(
        photoUrl: entry.photoUrl,
        name: entry.displayName,
        lastName: entry.lastInitial,
        isGoalkeeper: entry.isGoalkeeper,
        size: 24,
      ),
      label: Text(entry.displayName),
      onPressed: onTap,
    );
    if (!editable || !entry.canBeSelected) return chip;
    return LongPressDraggable<MatchCompositionEntry>(
      data: entry,
      feedback: Material(type: MaterialType.transparency, child: chip),
      childWhenDragging: Opacity(opacity: 0.3, child: chip),
      child: chip,
    );
  }
}

class CompositionDropZone extends StatelessWidget {
  const CompositionDropZone({
    super.key,
    required this.title,
    required this.icon,
    required this.entries,
    required this.targetZone,
    required this.onMoved,
    required this.onPlayerTap,
    this.subtitle,
    this.acceptDrops = true,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final List<MatchCompositionEntry> entries;
  final MatchCompositionZone targetZone;
  final void Function(
    MatchCompositionEntry entry,
    MatchCompositionZone zone,
    Offset? normalizedPosition,
  ) onMoved;
  final ValueChanged<MatchCompositionEntry> onPlayerTap;
  final bool acceptDrops;

  @override
  Widget build(BuildContext context) {
    return DragTarget<MatchCompositionEntry>(
      onWillAcceptWithDetails: (details) =>
          acceptDrops && details.data.canBeSelected,
      onAcceptWithDetails: (details) => onMoved(details.data, targetZone, null),
      builder: (context, candidates, rejected) {
        final highlighted = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: highlighted ? AppTheme.surfaceHigh : AppTheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: highlighted ? AppTheme.accent : AppTheme.outline,
              width: highlighted ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$title (${entries.length})',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w400,
                          ),
                    ),
                  ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 10),
              if (entries.isEmpty)
                Text(
                  acceptDrops ? 'Dépose un joueur ici.' : 'Aucun joueur.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in entries)
                      CompositionPlayerChip(
                        entry: entry,
                        editable: acceptDrops,
                        onTap: () => onPlayerTap(entry),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class CompositionPlayerTile extends StatelessWidget {
  const CompositionPlayerTile({super.key, required this.entry, this.onTap});

  final MatchCompositionEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (entry.isVacant) return const VacantSlotMarker();
    final label = entry.displayName.trim();
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 60,
            height: 64,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Align(
                  alignment: Alignment.bottomCenter,
                  child: PlayerAvatar(
                    photoUrl: entry.photoUrl,
                    name: entry.displayName,
                    lastName: entry.lastInitial,
                    isGoalkeeper: entry.isGoalkeeper,
                    size: 52,
                  ),
                ),
                if (entry.isMotm)
                  const Positioned(
                    top: -4,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text('👑', style: TextStyle(fontSize: 20)),
                    ),
                  ),
                if (entry.goals > 0)
                  Positioned(
                    left: 0,
                    top: 40,
                    child: GoalBadge(goals: entry.goals),
                  ),
                if (entry.assists > 0)
                  Positioned(
                    left: 0,
                    top: 53,
                    child: AssistBadge(assists: entry.assists),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          PitchPlayerName(label: label),
        ],
      ),
    );
  }
}

/// Emplacement du terrain dont le joueur est inconnu, sur une composition
/// reconstruite depuis les archives du club : une case grise barrée d'un
/// tiret, sans photo, sans initiales et sans nom, pour qu'on lise « on ne
/// sait pas qui jouait là » au lieu d'un joueur qui n'a jamais existé.
class VacantSlotMarker extends StatelessWidget {
  const VacantSlotMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: "Poste sans joueur connu dans l'archive",
      child: ExcludeSemantics(
        child: SizedBox(
          width: 60,
          height: 64,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0x33000000),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white38, width: 2),
              ),
              child: const Center(
                child: Text(
                  '\u2014',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w400,
                    fontSize: 18,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ballon « but » posé sur le côté de la photo d'un joueur, sur le modèle
/// des feuilles de match Flashscore : un unique ⚽ (peu importe le nombre
/// de buts), sans pastille ni contour, avec un petit chiffre en
/// surimpression au coin supérieur quand le joueur a inscrit plus d'un
/// but. Partagé par la composition Live et la fiche d'un match archivé
/// pour que les deux affichages restent visuellement identiques.
class GoalBadge extends StatelessWidget {
  const GoalBadge({super.key, required this.goals});

  final int goals;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Text('⚽', style: TextStyle(fontSize: 11, height: 1)),
        if (goals > 1)
          Positioned(
            top: -5,
            right: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
              decoration: BoxDecoration(
                color: const Color(0xFF2E3A59),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.white70, width: 0.5),
              ),
              child: Text(
                '$goals',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w400,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Crampon « passe décisive » placé juste sous le ballon. Le comportement est
/// volontairement identique à [GoalBadge] : une seule icône, puis un petit
/// compteur en surimpression uniquement à partir de deux passes décisives.
class AssistBadge extends StatelessWidget {
  const AssistBadge({super.key, required this.assists});

  final int assists;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Text('👟', style: TextStyle(fontSize: 11, height: 1)),
        if (assists > 1)
          Positioned(
            top: -5,
            right: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
              decoration: BoxDecoration(
                color: const Color(0xFF2E3A59),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.white70, width: 0.5),
              ),
              child: Text(
                '$assists',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w400,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class SubstituteHistoryBadge extends StatelessWidget {
  const SubstituteHistoryBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFF2E3A59),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white70, width: .8),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w400,
          height: 1,
        ),
      ),
    );
  }
}

class PlayerAvatar extends StatefulWidget {
  const PlayerAvatar({
    super.key,
    required this.photoUrl,
    required this.name,
    this.lastName,
    this.isGoalkeeper = false,
    this.size = 52,
    this.fallbackScale = .84,
  });

  final String? photoUrl;
  final String name;

  /// Nom de famille, ou son initiale. Il n'entre plus dans les initiales,
  /// calculées sur le seul nom affiché pour être les mêmes sur tous les
  /// écrans (voir [avatarInitials]).
  final String? lastName;
  final bool isGoalkeeper;
  final double size;

  /// Les initiales restent dans le même emplacement que la photo, mais leur
  /// carré est volontairement plus petit pour ne jamais dominer ni déborder
  /// visuellement sur les compositions compactes.
  final double fallbackScale;

  @override
  State<PlayerAvatar> createState() => _PlayerAvatarState();
}

class _PlayerAvatarState extends State<PlayerAvatar> {
  static const _avatarPalette = <List<Color>>[
    [Color(0xFF7C4DFF), Color(0xFF5E35B1)],
    [Color(0xFF2E86DE), Color(0xFF1B4F91)],
    [Color(0xFF17A589), Color(0xFF0E6B57)],
    [Color(0xFFE84393), Color(0xFFB61E74)],
    [Color(0xFF00A8E8), Color(0xFF006C93)],
    [Color(0xFF27AE60), Color(0xFF1E7A45)],
    [Color(0xFFE74C3C), Color(0xFF992D22)],
    [Color(0xFF00B2A9), Color(0xFF00807A)],
    [Color(0xFF8E44AD), Color(0xFF5E2C72)],
    [Color(0xFF546E7A), Color(0xFF37474F)],
  ];

  /// Une seule nouvelle signature après un échec de chargement. Au-delà, la
  /// photo est considérée comme indisponible : réessayer en boucle ne faisait
  /// que multiplier les requêtes sans jamais rien afficher.
  static const _maxRetries = 1;

  int _attempt = 0;
  String? _resolvedPhotoUrl;

  @override
  void initState() {
    super.initState();
    // Une URL déjà signée est réutilisée immédiatement : la photo apparaît dès
    // la première image, sans passer par les initiales.
    _resolvedPhotoUrl = ProfilePhotoUrlCache.instance.cached(widget.photoUrl);
    if (_resolvedPhotoUrl == null) _resolvePhoto();
  }

  @override
  void didUpdateWidget(PlayerAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoUrl != widget.photoUrl) {
      _attempt = 0;
      _resolvedPhotoUrl = ProfilePhotoUrlCache.instance.cached(widget.photoUrl);
      if (_resolvedPhotoUrl == null) _resolvePhoto();
    }
  }

  List<Color> get _avatarColors {
    final seed = widget.name.trim().toLowerCase();
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _avatarPalette[hash % _avatarPalette.length];
  }

  Future<void> _resolvePhoto() async {
    final original = widget.photoUrl?.trim();
    if (original == null || original.isEmpty) return;
    final signed = await ProfilePhotoUrlCache.instance.resolve(original);
    if (!mounted || widget.photoUrl?.trim() != original) return;
    if (signed == _resolvedPhotoUrl) return;
    setState(() => _resolvedPhotoUrl = signed);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final fallbackScale = widget.fallbackScale.clamp(.5, 1).toDouble();
    final fallbackSize = size * fallbackScale;
    final border = widget.isGoalkeeper ? const Color(0xFFE59A1F) : Colors.white;
    final original = widget.photoUrl?.trim();
    final hasPhoto = original != null && original.isNotEmpty;
    final url = _resolvedPhotoUrl;
    final showPhoto = hasPhoto && url != null;
    final visualSize = showPhoto ? size : fallbackSize;

    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Container(
          width: visualSize,
          height: visualSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(visualSize * 0.28),
            border: showPhoto ? null : Border.all(color: border, width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: showPhoto ? _photo(url) : _initials(visualSize),
        ),
      ),
    );
  }

  Widget _initials(double visualSize) {
    final initials = avatarInitials(widget.name);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _avatarColors,
        ),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w400,
            fontSize: visualSize * 0.32,
            shadows: const [Shadow(color: Colors.black26, blurRadius: 2)],
          ),
        ),
      ),
    );
  }

  Widget _photo(String url) {
    final fallbackSize =
        widget.size * widget.fallbackScale.clamp(.5, 1).toDouble();
    return Image.network(
      url,
      key: ValueKey('$url#$_attempt'),
      width: widget.size,
      height: widget.size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      // Les vues HTML créent un overlay de composition par avatar sur le Web.
      // Sur iOS, la grille d'effectif pouvait ainsi dépasser les ressources de
      // WebKit et faire recharger toute la page. Supabase autorise le chargement
      // CORS des URLs signées : Flutter peut donc décoder l'image normalement.
      // On ne retombe sur un élément HTML que pour une éventuelle URL externe
      // qui refuserait le chargement CORS.
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : _initials(fallbackSize),
      errorBuilder: (context, error, stack) {
        if (_attempt < _maxRetries) {
          // Une URL signée peut avoir expiré ou pointer vers un fichier
          // supprimé : on l'oublie et on en redemande une neuve, une fois.
          ProfilePhotoUrlCache.instance.invalidate(widget.photoUrl);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _attempt += 1;
              _resolvedPhotoUrl = null;
            });
            _resolvePhoto();
          });
        }
        return _initials(fallbackSize);
      },
    );
  }
}

/// Traçage des lignes d'un terrain de foot. Public afin d'être partagé par
/// la composition Live et par la fiche d'un match archivé : les deux
/// affichages doivent rester visuellement identiques.
