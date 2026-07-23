import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:flutter/material.dart';

class FormationPitchEditor extends StatelessWidget {
  const FormationPitchEditor({
    super.key,
    required this.slots,
    required this.entries,
    required this.onDroppedOnSlot,
    required this.onRemoveFromField,
    this.editable = true,
  });

  final List<FootballFormationSlot> slots;
  final List<MatchCompositionEntry> entries;
  final void Function(
    MatchCompositionEntry entry,
    FootballFormationSlot slot,
  ) onDroppedOnSlot;
  final ValueChanged<MatchCompositionEntry> onRemoveFromField;
  final bool editable;

  MatchCompositionEntry? _entryFor(FootballFormationSlot slot) {
    MatchCompositionEntry? closest;
    var distance = double.infinity;
    for (final entry in entries) {
      final current = Offset(entry.x ?? .5, entry.y ?? .5);
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
            return DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF174936),
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
                        child: CustomPaint(painter: _PitchPainter())),
                    for (final slot in slots)
                      _slot(
                          context, constraints.biggest, slot, _entryFor(slot)),
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
  ) {
    // La feuille de match affiche 22 postes : on garde des marqueurs
    // compacts (carrés) pour qu'ils tiennent sans se chevaucher sur mobile.
    // Le joueur placé occupe le même carré que l'emplacement vide.
    const width = 58.0;
    const height = 58.0;
    final left = (slot.position.dx * size.width - width / 2)
        .clamp(0.0, size.width - width)
        .toDouble();
    final top = (slot.position.dy * size.height - height / 2)
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
            return AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              decoration: BoxDecoration(
                color: highlighted
                    ? AppTheme.accent.withValues(alpha: .32)
                    : Colors.white.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: highlighted ? AppTheme.accent : Colors.white54,
                  width: highlighted ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add, color: Colors.white, size: 18),
                  Text(
                    slot.label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            );
          }

          final marker = Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: editable ? () => onRemoveFromField(entry) : null,
              borderRadius: BorderRadius.circular(16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
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
                // L'avatar occupe tout le carré (même taille qu'un emplacement
                // vide) ; le prénom est un bandeau en bas.
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PlayerAvatar(
                      photoUrl: entry.photoUrl,
                      name: entry.displayName,
                      isGoalkeeper: entry.isGoalkeeper,
                      size: width,
                    ),
                    Positioned(
                      left: 2,
                      right: 2,
                      bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .55),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          entry.displayName.trim().split(RegExp(r'\s+')).first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          if (!editable) return marker;
          return LongPressDraggable<MatchCompositionEntry>(
            data: entry,
            feedback: Material(
              type: MaterialType.transparency,
              child: SizedBox(width: width, height: height, child: marker),
            ),
            childWhenDragging: Opacity(opacity: .25, child: marker),
            child: marker,
          );
        },
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
    final inset = size.shortestSide * .045;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    canvas
      ..drawRect(rect, paint)
      ..drawLine(Offset(rect.left, rect.center.dy),
          Offset(rect.right, rect.center.dy), paint)
      ..drawCircle(rect.center, size.width * .13, paint)
      ..drawRect(
        Rect.fromCenter(
          center: Offset(rect.center.dx, rect.top + rect.height * .08),
          width: rect.width * .58,
          height: rect.height * .16,
        ),
        paint,
      )
      ..drawRect(
        Rect.fromCenter(
          center: Offset(rect.center.dx, rect.bottom - rect.height * .08),
          width: rect.width * .58,
          height: rect.height * .16,
        ),
        paint,
      );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
