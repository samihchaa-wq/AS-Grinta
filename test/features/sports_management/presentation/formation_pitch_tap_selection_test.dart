import 'package:as_grinta/features/match_live/presentation/widgets/live_bench_tile.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/formation_pitch_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MatchCompositionEntry _entry({
  required String id,
  required String name,
  required MatchCompositionZone zone,
  double? x,
  double? y,
}) {
  return MatchCompositionEntry(
    participantId: id,
    seasonPlayerId: id,
    displayName: name,
    isGoalkeeper: false,
    zone: zone,
    sortOrder: 0,
    availabilityStatus: 'available',
    convocationStatus: 'convoked',
    selectionStatus:
        zone == MatchCompositionZone.field ? 'starter' : 'substitute',
    x: x,
    y: y,
  );
}

Widget _harness({
  required List<FootballFormationSlot> slots,
  required List<MatchCompositionEntry> field,
  required void Function(MatchCompositionEntry, FootballFormationSlot) onDrop,
  MatchCompositionEntry? bench,
}) {
  const metrics = FormationMarkerMetrics(56);
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: SizedBox(
            width: 360,
            child: Column(
              children: [
                FormationPitchEditor(
                  slots: slots,
                  entries: field,
                  markerMetrics: metrics,
                  onDroppedOnSlot: onDrop,
                  onRemoveFromField: (_) {},
                ),
                if (bench != null) ...[
                  const SizedBox(height: 16),
                  LiveBenchTile(
                    entry: bench,
                    draggable: true,
                    metrics: metrics,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  const target = FootballFormationSlot(label: 'GB', position: Offset(.5, .85));
  const other = FootballFormationSlot(label: 'BU', position: Offset(.5, .12));

  testWidgets(
    'poste occupé puis remplaçant déclenche le placement sur ce poste',
    (tester) async {
      final starter = _entry(
        id: 'starter',
        name: 'Starter',
        zone: MatchCompositionZone.field,
        x: target.position.dx,
        y: target.position.dy,
      );
      final substitute = _entry(
        id: 'bench',
        name: 'Bench',
        zone: MatchCompositionZone.bench,
      );
      MatchCompositionEntry? moved;
      FootballFormationSlot? destination;

      await tester.pumpWidget(
        _harness(
          slots: const [target, other],
          field: [starter],
          bench: substitute,
          onDrop: (entry, slot) {
            moved = entry;
            destination = slot;
          },
        ),
      );

      await tester.tap(find.text('Starter'));
      await tester.pump(const Duration(milliseconds: 160));
      expect(FormationPitchTapSelection.hasSelection, isTrue);

      await tester.tap(find.text('Bench'));
      await tester.pump();

      expect(moved?.participantId, 'bench');
      expect(destination?.label, 'GB');
      expect(FormationPitchTapSelection.hasSelection, isFalse);
    },
  );

  testWidgets(
    'poste vide puis joueur place le joueur sur le poste sélectionné',
    (tester) async {
      final starter = _entry(
        id: 'starter',
        name: 'Starter',
        zone: MatchCompositionZone.field,
        x: target.position.dx,
        y: target.position.dy,
      );
      MatchCompositionEntry? moved;
      FootballFormationSlot? destination;

      await tester.pumpWidget(
        _harness(
          slots: const [target, other],
          field: [starter],
          onDrop: (entry, slot) {
            moved = entry;
            destination = slot;
          },
        ),
      );

      await tester.tap(find.text('BU'));
      await tester.pump(const Duration(milliseconds: 160));
      await tester.tap(find.text('Starter'));
      await tester.pump();

      expect(moved?.participantId, 'starter');
      expect(destination?.label, 'BU');
      expect(FormationPitchTapSelection.hasSelection, isFalse);
    },
  );

  testWidgets(
    'poste occupé puis autre titulaire prépare un échange de postes',
    (tester) async {
      final first = _entry(
        id: 'first',
        name: 'First',
        zone: MatchCompositionZone.field,
        x: target.position.dx,
        y: target.position.dy,
      );
      final second = _entry(
        id: 'second',
        name: 'Second',
        zone: MatchCompositionZone.field,
        x: other.position.dx,
        y: other.position.dy,
      );
      MatchCompositionEntry? moved;
      FootballFormationSlot? destination;

      await tester.pumpWidget(
        _harness(
          slots: const [target, other],
          field: [first, second],
          onDrop: (entry, slot) {
            moved = entry;
            destination = slot;
          },
        ),
      );

      await tester.tap(find.text('First'));
      await tester.pump(const Duration(milliseconds: 160));
      await tester.tap(find.text('Second'));
      await tester.pump();

      expect(moved?.participantId, 'second');
      expect(destination?.label, 'GB');
      expect(FormationPitchTapSelection.hasSelection, isFalse);
    },
  );
}
