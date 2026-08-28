import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/formation_pitch_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _slot = FootballFormationSlot(
  label: 'MC',
  position: Offset(.5, .5),
);

MatchCompositionEntry _entry({
  required String id,
  required String name,
  required MatchCompositionZone zone,
  double? x,
  double? y,
}) {
  return MatchCompositionEntry(
    participantId: id,
    seasonPlayerId: 'season-$id',
    displayName: name,
    isGoalkeeper: false,
    zone: zone,
    x: x,
    y: y,
    sortOrder: 0,
    availabilityStatus: 'available',
    convocationStatus: 'convoked',
    selectionStatus:
        zone == MatchCompositionZone.field ? 'starter' : 'substitute',
  );
}

Widget _harness({
  required MatchCompositionEntry starter,
  required void Function(
    MatchCompositionEntry entry,
    FootballFormationSlot slot,
  ) onDroppedOnSlot,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: FormationPitchEditor(
            slots: const [_slot],
            entries: [starter],
            onDroppedOnSlot: onDroppedOnSlot,
            onRemoveFromField: (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('banc puis titulaire déclenche le même remplacement au clic', (
    tester,
  ) async {
    final starter = _entry(
      id: 'starter',
      name: 'Titulaire',
      zone: MatchCompositionZone.field,
      x: .5,
      y: .5,
    );
    final substitute = _entry(
      id: 'substitute',
      name: 'Remplaçant',
      zone: MatchCompositionZone.bench,
    );
    MatchCompositionEntry? movedEntry;
    FootballFormationSlot? targetSlot;

    await tester.pumpWidget(
      _harness(
        starter: starter,
        onDroppedOnSlot: (entry, slot) {
          movedEntry = entry;
          targetSlot = slot;
        },
      ),
    );

    expect(FormationPitchTapSelection.placePlayer(substitute), isTrue);
    await tester.pump();
    expect(
      FormationPitchTapSelection.selectedParticipantId.value,
      substitute.participantId,
    );

    await tester.tap(find.byType(PlayerAvatar));
    await tester.pump();

    expect(movedEntry?.participantId, substitute.participantId);
    expect(targetSlot?.label, _slot.label);
    expect(FormationPitchTapSelection.hasSelection, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('titulaire puis banc reste fonctionnel', (tester) async {
    final starter = _entry(
      id: 'starter',
      name: 'Titulaire',
      zone: MatchCompositionZone.field,
      x: .5,
      y: .5,
    );
    final substitute = _entry(
      id: 'substitute',
      name: 'Remplaçant',
      zone: MatchCompositionZone.bench,
    );
    MatchCompositionEntry? movedEntry;

    await tester.pumpWidget(
      _harness(
        starter: starter,
        onDroppedOnSlot: (entry, _) => movedEntry = entry,
      ),
    );

    await tester.tap(find.byType(PlayerAvatar));
    await tester.pump();
    expect(FormationPitchTapSelection.hasSelection, isTrue);

    expect(FormationPitchTapSelection.placePlayer(substitute), isTrue);
    await tester.pump();

    expect(movedEntry?.participantId, substitute.participantId);
    expect(FormationPitchTapSelection.hasSelection, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
