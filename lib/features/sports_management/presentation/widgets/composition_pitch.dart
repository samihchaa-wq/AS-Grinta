import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
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
                    color: highlighted
                        ? const Color(0xFF205E48)
                        : const Color(0xFF174936),
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
                        const Positioned.fill(
                          child: CustomPaint(painter: _PitchPainter()),
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
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
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

    final marker = _PlayerMarker(
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
                            fontWeight: FontWeight.w900,
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

class _PlayerMarker extends StatelessWidget {
  const _PlayerMarker({required this.entry, this.onTap});

  final MatchCompositionEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
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
                    isGoalkeeper: entry.isGoalkeeper,
                    size: 52,
                  ),
                ),
                // La couronne de l'HDM passe derrière les ballons.
                if (entry.isMotm)
                  const Positioned(
                    top: 6,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text('👑', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                if (entry.goals > 0)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Center(child: _GoalBalls(goals: entry.goals)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
            ),
          ),
        ],
      ),
    );
  }
}

/// Petits ballons collés au-dessus de la photo indiquant le nombre de buts.
class _GoalBalls extends StatelessWidget {
  const _GoalBalls({required this.goals});

  final int goals;

  @override
  Widget build(BuildContext context) {
    final count = goals.clamp(1, 6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            const Text('⚽', style: TextStyle(fontSize: 11, height: 1)),
          if (goals > 6)
            const Padding(
              padding: EdgeInsets.only(left: 1),
              child: Text(
                '+',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Vignette d'un joueur : photo si disponible, sinon initiales.
/// Utilisée uniquement sur les compositions.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.photoUrl,
    required this.name,
    this.isGoalkeeper = false,
    this.size = 52,
  });

  final String? photoUrl;
  final String name;
  final bool isGoalkeeper;
  final double size;

  // Palette d'avatars « aléatoires » (stables par joueur, dérivés du nom).
  static const _avatarPalette = <List<Color>>[
    [Color(0xFF7C4DFF), Color(0xFF5E35B1)],
    [Color(0xFF2E86DE), Color(0xFF1B4F91)],
    [Color(0xFF17A589), Color(0xFF0E6B57)],
    [Color(0xFFE84393), Color(0xFFB61E74)],
    [Color(0xFFE67E22), Color(0xFFB35900)],
    [Color(0xFF27AE60), Color(0xFF1E7A45)],
    [Color(0xFFE74C3C), Color(0xFF992D22)],
    [Color(0xFF00B2A9), Color(0xFF00807A)],
    [Color(0xFF8E44AD), Color(0xFF5E2C72)],
    [Color(0xFFF39C12), Color(0xFFB9770E)],
  ];

  List<Color> get _avatarColors {
    final seed = name.trim().toLowerCase();
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _avatarPalette[hash % _avatarPalette.length];
  }

  @override
  Widget build(BuildContext context) {
    final border = isGoalkeeper ? const Color(0xFFE59A1F) : Colors.white;
    final url = photoUrl;
    final hasPhoto = url != null && url.isNotEmpty;
    final colors = _avatarColors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: hasPhoto
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
        color: hasPhoto ? const Color(0xFF2A2350) : null,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: border, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _initials(),
            )
          : _initials(),
    );
  }

  Widget _initials() {
    final word = name.trim().split(RegExp(r'\s+')).first;
    final initials = word.isEmpty
        ? '?'
        : (word.length >= 2 ? word.substring(0, 2) : word).toUpperCase();
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.32,
          shadows: const [Shadow(color: Colors.black26, blurRadius: 2)],
        ),
      ),
    );
  }
}

class _PitchPainter extends CustomPainter {
  const _PitchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xAAFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final inset = size.shortestSide * 0.045;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    canvas.drawRect(rect, paint);
    canvas.drawLine(
      Offset(rect.left, rect.center.dy),
      Offset(rect.right, rect.center.dy),
      paint,
    );
    canvas.drawCircle(rect.center, size.width * 0.13, paint);
    canvas.drawCircle(rect.center, 2.5, paint..style = PaintingStyle.fill);
    paint.style = PaintingStyle.stroke;

    final penaltyWidth = rect.width * 0.58;
    final penaltyHeight = rect.height * 0.16;
    final topPenalty = Rect.fromCenter(
      center: Offset(rect.center.dx, rect.top + penaltyHeight / 2),
      width: penaltyWidth,
      height: penaltyHeight,
    );
    final bottomPenalty = Rect.fromCenter(
      center: Offset(rect.center.dx, rect.bottom - penaltyHeight / 2),
      width: penaltyWidth,
      height: penaltyHeight,
    );
    canvas.drawRect(topPenalty, paint);
    canvas.drawRect(bottomPenalty, paint);

    final goalWidth = rect.width * 0.30;
    final goalDepth = rect.height * 0.025;
    canvas.drawRect(
      Rect.fromLTWH(
        rect.center.dx - goalWidth / 2,
        rect.top - goalDepth,
        goalWidth,
        goalDepth,
      ),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        rect.center.dx - goalWidth / 2,
        rect.bottom,
        goalWidth,
        goalDepth,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
