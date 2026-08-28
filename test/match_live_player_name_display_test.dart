import 'package:as_grinta/features/match_live/presentation/match_live_running_page.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/live_bench_tile.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/formation_pitch_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// Régression : sur le Tableau Blanc en cours de match, le terrain se resserre
// pour laisser la place au banc. « François » s'affichait alors « Franç… ».
const _longName = 'François';

void main() {
  test('l’étiquette du prénom peut déborder du marqueur', () {
    final metrics = benchAndPitchMetrics(365);
    expect(metrics.nameMaxWidth, greaterThan(metrics.width));
    expect(metrics.nameHeight, greaterThan(metrics.nameFontSize));
  });

  testWidgets('un prénom long n’est pas tronqué sur le terrain', (
    tester,
  ) async {
    // Largeur utile d'un téléphone courant, une fois les marges du cockpit
    // Live retirées.
    final metrics = benchAndPitchMetrics(365);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 296,
              child: FormationPitchEditor(
                slots: formationForCode('4-2-1-3').slots,
                entries: [_entry(_longName, 0.5, 0.9)],
                markerMetrics: metrics,
                onDroppedOnSlot: (_, __) {},
                onRemoveFromField: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    _expectNotTruncated(tester, _longName);
  });

  testWidgets('un prénom long n’est pas tronqué sur le banc', (tester) async {
    final metrics = benchAndPitchMetrics(365);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: LiveBenchTile(
              entry: _entry(_longName, null, null),
              draggable: false,
              metrics: metrics,
            ),
          ),
        ),
      ),
    );

    _expectNotTruncated(tester, _longName);
  });
}

/// Le prénom doit être rendu en entier. `didExceedMaxLines` est vrai dès que
/// la ligne est rabotée — c'est exactement le « Franç… » constaté en match.
void _expectNotTruncated(WidgetTester tester, String label) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: 'le prénom « $label » doit tenir sans être coupé',
  );
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: TextDirection.ltr,
  )..layout();
  expect(
    paragraph.size.width,
    greaterThanOrEqualTo(painter.width - 0.5),
    reason: 'le prénom « $label » doit être mis en page dans sa largeur '
        'naturelle, puis réduit si besoin',
  );
}

MatchCompositionEntry _entry(String name, double? x, double? y) =>
    MatchCompositionEntry(
      participantId: 'p-$name',
      seasonPlayerId: 'sp-$name',
      displayName: name,
      isGoalkeeper: false,
      zone: x == null ? MatchCompositionZone.bench : MatchCompositionZone.field,
      x: x,
      y: y,
      sortOrder: 0,
      availabilityStatus: 'available',
      convocationStatus: 'convoked',
      selectionStatus: 'starter',
    );
