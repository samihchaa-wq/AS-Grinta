import 'package:as_grinta/features/match_live/domain/match_live_formation.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('changing formation only repositions current field players', () {
    final lineup = MatchComposition(
      matchId: 'match-1',
      formationCode: '4-2-1-3',
      status: 'published',
      version: 1,
      hasUnpublishedChanges: false,
      squadSizeExceptionApproved: false,
      entries: const [
        MatchCompositionEntry(
          participantId: 'keeper',
          seasonPlayerId: 'sp-keeper',
          displayName: 'Keeper',
          isGoalkeeper: true,
          zone: MatchCompositionZone.field,
          x: .5,
          y: .85,
          sortOrder: 0,
          availabilityStatus: 'available',
          convocationStatus: 'convoked',
          selectionStatus: 'starter',
        ),
        MatchCompositionEntry(
          participantId: 'player-a',
          seasonPlayerId: 'sp-a',
          displayName: 'Player A',
          isGoalkeeper: false,
          zone: MatchCompositionZone.field,
          x: .2,
          y: .4,
          sortOrder: 1,
          availabilityStatus: 'available',
          convocationStatus: 'convoked',
          selectionStatus: 'starter',
        ),
        MatchCompositionEntry(
          participantId: 'player-b',
          seasonPlayerId: 'sp-b',
          displayName: 'Player B',
          isGoalkeeper: false,
          zone: MatchCompositionZone.field,
          x: .8,
          y: .4,
          sortOrder: 2,
          availabilityStatus: 'available',
          convocationStatus: 'convoked',
          selectionStatus: 'starter',
        ),
        MatchCompositionEntry(
          participantId: 'bench',
          seasonPlayerId: 'sp-bench',
          displayName: 'Bench',
          isGoalkeeper: false,
          zone: MatchCompositionZone.bench,
          sortOrder: 0,
          availabilityStatus: 'available',
          convocationStatus: 'convoked',
          selectionStatus: 'substitute',
        ),
      ],
    );

    final changed = repositionLiveLineupForFormation(lineup, '3-5-2');
    final slots = formationForCode('3-5-2').slots;

    expect(changed.formationCode, '3-5-2');
    expect(changed.fieldCount, 3);
    expect(changed.benchCount, 1);

    final fieldById = {
      for (final entry in changed.entriesFor(MatchCompositionZone.field))
        entry.participantId: entry,
    };
    expect(fieldById['keeper']!.x, slots[0].position.dx);
    expect(fieldById['keeper']!.y, slots[0].position.dy);
    expect(fieldById['player-a']!.x, slots[1].position.dx);
    expect(fieldById['player-a']!.y, slots[1].position.dy);
    expect(fieldById['player-b']!.x, slots[2].position.dx);
    expect(fieldById['player-b']!.y, slots[2].position.dy);

    final bench = changed.entriesFor(MatchCompositionZone.bench).single;
    expect(bench.participantId, 'bench');
    expect(bench.x, isNull);
    expect(bench.y, isNull);
  });
}
