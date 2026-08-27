import 'package:as_grinta/core/widgets/composition_drag.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/live_bench_tile.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
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

/// Glisse [from] et relâche en [globalTarget], en respectant l'appui long
/// tactile de [CompositionDraggable].
Future<void> _dragAndDrop(
  WidgetTester tester,
  Finder from,
  Offset globalTarget,
) async {
  final gesture = await tester.startGesture(tester.getCenter(from));
  await tester.pump(
    kCompositionDragTouchDelay + const Duration(milliseconds: 60),
  );
  await gesture.moveTo(globalTarget);
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

/// Point global correspondant à une position normalisée du terrain.
Offset _pitchPoint(WidgetTester tester, Finder pitch, Offset normalized) {
  final rect = tester.getRect(pitch);
  return Offset(
    rect.left + normalized.dx * rect.width,
    rect.top + normalized.dy * rect.height,
  );
}

void main() {
  const goalkeeper =
      FootballFormationSlot(label: 'GB', position: Offset(.5, .85));
  const striker = FootballFormationSlot(label: 'BU', position: Offset(.5, .12));

  Widget pitchHarness({
    required List<MatchCompositionEntry> field,
    required ValueChanged<FormationDrop> onDrop,
    MatchCompositionEntry? bench,
  }) {
    const metrics = FormationMarkerMetrics(56);
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FormationPitchEditor(
                  slots: const [goalkeeper, striker],
                  entries: field,
                  markerMetrics: metrics,
                  onDroppedOnSlot: onDrop,
                  onRemoveFromField: (_) {},
                ),
                if (bench != null) ...[
                  const SizedBox(height: 8),
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
    );
  }

  testWidgets(
    'un joueur relâché entre deux postes rejoint le plus proche',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final substitute = _entry(
        id: 'bench',
        name: 'Bench',
        zone: MatchCompositionZone.bench,
      );
      FormationDrop? received;

      await tester.pumpWidget(
        pitchHarness(
          field: const [],
          bench: substitute,
          onDrop: (drop) => received = drop,
        ),
      );

      final pitch = find.byType(FormationPitchEditor);
      // .60 en hauteur ne touche aucune vignette de poste : le gardien est à
      // .85 et l'attaquant à .12. Avant, le dépôt tombait dans le vide et
      // rien ne se produisait.
      await _dragAndDrop(
        tester,
        find.text('Bench'),
        _pitchPoint(tester, pitch, const Offset(.5, .60)),
      );

      expect(received, isNotNull);
      expect(received!.entry.participantId, 'bench');
      expect(received!.slot.label, 'GB');
      expect(received!.occupant, isNull);
    },
  );

  testWidgets(
    'le poste visé est bien celui du point relâché, pas le voisin',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final substitute = _entry(
        id: 'bench',
        name: 'Bench',
        zone: MatchCompositionZone.bench,
      );
      FormationDrop? received;

      await tester.pumpWidget(
        pitchHarness(
          field: const [],
          bench: substitute,
          onDrop: (drop) => received = drop,
        ),
      );

      final pitch = find.byType(FormationPitchEditor);
      await _dragAndDrop(
        tester,
        find.text('Bench'),
        _pitchPoint(tester, pitch, const Offset(.5, .30)),
      );

      expect(received?.slot.label, 'BU');
    },
  );

  testWidgets(
    'déposer sur un titulaire désigne ce titulaire comme joueur à échanger',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final starter = _entry(
        id: 'starter',
        name: 'Starter',
        zone: MatchCompositionZone.field,
        x: goalkeeper.position.dx,
        y: goalkeeper.position.dy,
      );
      final substitute = _entry(
        id: 'bench',
        name: 'Bench',
        zone: MatchCompositionZone.bench,
      );
      FormationDrop? received;

      await tester.pumpWidget(
        pitchHarness(
          field: [starter],
          bench: substitute,
          onDrop: (drop) => received = drop,
        ),
      );

      final pitch = find.byType(FormationPitchEditor);
      await _dragAndDrop(
        tester,
        find.text('Bench'),
        _pitchPoint(tester, pitch, goalkeeper.position),
      );

      expect(received?.slot.label, 'GB');
      expect(received?.occupant?.participantId, 'starter');
    },
  );

  testWidgets(
    'deux titulaires collés au même poste restent tous les deux affichés',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Les deux joueurs sont plus proches du gardien que de l'attaquant :
      // l'ancien calcul, poste par poste, les faisait tous deux atterrir sur
      // le gardien — l'un s'affichait en double, l'autre disparaissait.
      final first = _entry(
        id: 'first',
        name: 'First',
        zone: MatchCompositionZone.field,
        x: .50,
        y: .84,
      );
      final second = _entry(
        id: 'second',
        name: 'Second',
        zone: MatchCompositionZone.field,
        x: .52,
        y: .80,
      );

      await tester.pumpWidget(
        pitchHarness(field: [first, second], onDrop: (_) {}),
      );

      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
    },
  );

  testWidgets(
    'sur un terrain libre, le joueur atterrit là où on voit sa vignette',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final player = _entry(
        id: 'player',
        name: 'Player',
        zone: MatchCompositionZone.field,
        x: .5,
        y: .8,
      );
      Offset? dropped;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: CompositionPitch(
                  entries: [player],
                  editable: true,
                  onMoved: (entry, zone, normalized) => dropped = normalized,
                ),
              ),
            ),
          ),
        ),
      );

      final pitch = find.byType(CompositionPitch);
      const release = Offset(.35, .40);
      await _dragAndDrop(
        tester,
        find.text('Player'),
        _pitchPoint(tester, pitch, release),
      );

      expect(dropped, isNotNull);
      // La vignette est dessinée centrée sur le doigt puis remontée de 45 %
      // de sa hauteur (84 px sur ce terrain) : le joueur doit atterrir là où
      // on voyait sa photo, pas ailleurs.
      final pitchHeight = tester.getRect(pitch).height;
      final expected = Offset(
        release.dx,
        release.dy - (84 * .45) / pitchHeight,
      );
      // Avant, le point enregistré était celui du coin haut-gauche de la
      // vignette fantôme, décalé en plus d'une demi-largeur de vignette.
      expect((dropped!.dx - expected.dx).abs(), lessThan(.02));
      expect((dropped!.dy - expected.dy).abs(), lessThan(.02));
    },
  );
}
