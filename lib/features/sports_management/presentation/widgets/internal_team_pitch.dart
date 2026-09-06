import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/internal_match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/internal_team_formation.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart'
    show PlayerAvatar;
import 'package:as_grinta/features/sports_management/presentation/widgets/football_pitch.dart';
import 'package:flutter/material.dart';

/// Terrain compact d'une équipe « entre nous ».
///
/// Le contrôle est d'abord pensé pour le tactile : sélectionner un joueur puis
/// toucher un emplacement suffit. Le drag & drop n'est volontairement pas une
/// condition d'utilisation.
class InternalTeamPitch extends StatelessWidget {
  const InternalTeamPitch({
    super.key,
    required this.formation,
    required this.entries,
    required this.editable,
    required this.selectedParticipantId,
    required this.onSlotTap,
  });

  final InternalTeamFormation formation;
  final List<InternalCompositionEntry> entries;
  final bool editable;
  final String? selectedParticipantId;
  final void Function(
    FootballFormationSlot slot,
    InternalCompositionEntry? occupant,
  ) onSlotTap;

  @override
  Widget build(BuildContext context) {
    final bySlot = <String, InternalCompositionEntry>{
      for (final entry in entries)
        if (entry.slotLabel case final slot?) slot: entry,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = (width * 1.42).clamp(260.0, 520.0).toDouble();
        final markerWidth = (width / 5.2).clamp(44.0, 62.0).toDouble();
        final markerHeight = markerWidth * 1.28;
        final hasSelection = selectedParticipantId != null;

        return SizedBox(
          width: width,
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: FootballPitchPainter(highlighted: hasSelection),
                  ),
                ),
                for (final slot in formation.slots)
                  Positioned(
                    left: slot.position.dx * width - markerWidth / 2,
                    top: slot.position.dy * height - markerHeight / 2,
                    width: markerWidth,
                    height: markerHeight,
                    child: _InternalPitchSlot(
                      slot: slot,
                      occupant: bySlot[slot.label],
                      editable: editable,
                      selected: bySlot[slot.label]?.participantId ==
                          selectedParticipantId,
                      assignmentTarget: editable && hasSelection,
                      markerWidth: markerWidth,
                      onTap: () => onSlotTap(slot, bySlot[slot.label]),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InternalPitchSlot extends StatelessWidget {
  const _InternalPitchSlot({
    required this.slot,
    required this.occupant,
    required this.editable,
    required this.selected,
    required this.assignmentTarget,
    required this.markerWidth,
    required this.onTap,
  });

  final FootballFormationSlot slot;
  final InternalCompositionEntry? occupant;
  final bool editable;
  final bool selected;
  final bool assignmentTarget;
  final double markerWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final player = occupant;
    final content = player == null
        ? _EmptySlot(
            label: slot.label,
            active: assignmentTarget,
            size: markerWidth * .58,
          )
        : _PlayerMarker(
            entry: player,
            selected: selected,
            width: markerWidth,
          );

    return Semantics(
      button: editable,
      selected: selected,
      label: player == null
          ? 'Poste ${slot.label}, libre'
          : '${player.displayName}, poste ${slot.label}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: editable ? onTap : null,
          child: content,
        ),
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({
    required this.label,
    required this.active,
    required this.size,
  });

  final String label;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xB3071527),
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? AppTheme.accent : Colors.white70,
            width: active ? 2.5 : 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: (size * .24).clamp(9.0, 12.0).toDouble(),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PlayerMarker extends StatelessWidget {
  const _PlayerMarker({
    required this.entry,
    required this.selected,
    required this.width,
  });

  final InternalCompositionEntry entry;
  final bool selected;
  final double width;

  @override
  Widget build(BuildContext context) {
    final avatarSize = width * .72;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      decoration: BoxDecoration(
        color: selected
            ? AppTheme.accent.withValues(alpha: .18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? AppTheme.accent : Colors.transparent,
          width: selected ? 2 : 0,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PlayerAvatar(
            photoUrl: entry.photoUrl,
            name: entry.displayName,
            lastName: entry.lastInitial,
            isGoalkeeper: entry.slotLabel == 'GB',
            size: avatarSize,
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: width * 1.25,
            child: PitchPlayerName(
              label: entry.displayName,
              fontSize: (width * .18).clamp(9.5, 11.5).toDouble(),
            ),
          ),
        ],
      ),
    );
  }
}
