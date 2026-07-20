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
    const markerWidth = 82.0;
    const markerHeight = 52.0;
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
      avatar: Icon(
        entry.isGoalkeeper ? Icons.sports_handball : Icons.person_outline,
        size: 18,
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
    final firstName = entry.displayName.trim().split(RegExp(r'\s+')).first;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color:
                entry.isGoalkeeper ? const Color(0xFFE59A1F) : AppTheme.primary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white70),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                entry.isGoalkeeper
                    ? Icons.sports_handball
                    : Icons.sports_soccer,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(height: 2),
              Text(
                firstName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
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
