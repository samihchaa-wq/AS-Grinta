import 'package:as_grinta/features/matches/presentation/widgets/completed_match_composition_card.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MatchCompositionEntry _entry({
  required String name,
  required int sortOrder,
  required double x,
  required double y,
  bool isVacant = false,
}) {
  return MatchCompositionEntry(
    participantId: 'entry-$sortOrder',
    seasonPlayerId: name,
    displayName: name,
    isGoalkeeper: false,
    zone: MatchCompositionZone.field,
    sortOrder: sortOrder,
    availabilityStatus: 'available',
    convocationStatus: isVacant ? 'not_applicable' : 'convoked',
    selectionStatus: 'starter',
    x: x,
    y: y,
    isVacant: isVacant,
  );
}

MatchComposition _composition(List<MatchCompositionEntry> entries) {
  return MatchComposition(
    matchId: 'match-archive',
    formationCode: '4-1-4-1',
    status: 'published',
    version: 1,
    hasUnpublishedChanges: false,
    squadSizeExceptionApproved: false,
    entries: entries,
  );
}

Widget _harness(MatchComposition composition) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: CompletedCompositionCard(
          composition: composition,
          fallbackPlayers: const [],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('un emplacement vide s’affiche en case grisée, sans nom', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        _composition([
          _entry(name: 'Milan', sortOrder: 0, x: .5, y: .05),
          _entry(name: '', sortOrder: 1, x: .1, y: .68, isVacant: true),
        ]),
      ),
    );
    await tester.pump();

    expect(find.text('Milan'), findsOneWidget);
    expect(find.byType(VacantSlotMarker), findsOneWidget);
    // Aucune initiale ni aucun nom inventé pour le trou de la feuille de match.
    expect(find.textContaining('Poste'), findsNothing);
    expect(find.textContaining('emplacements grisés'), findsOneWidget);
  });

  testWidgets('sans emplacement vide, aucune explication superflue', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        _composition([_entry(name: 'Milan', sortOrder: 0, x: .5, y: .05)]),
      ),
    );
    await tester.pump();

    expect(find.byType(VacantSlotMarker), findsNothing);
    expect(find.textContaining('emplacements grisés'), findsNothing);
  });
}
