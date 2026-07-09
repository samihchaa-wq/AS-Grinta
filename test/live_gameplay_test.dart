import 'package:as_grinta/features/live/domain/live_gameplay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LiveGameplayState', () {
    test('moves a player from the bench to a slot and keeps the slot unique',
        () {
      final state = LiveGameplayState.initial(
        players: [
          const LivePlayer(id: 'p1', name: 'Alice'),
          const LivePlayer(id: 'p2', name: 'Bob'),
        ],
        formationKey: '4-4-2',
      );

      state.movePlayer(playerId: 'p1', slotKey: 'st');
      expect(state.lineup['st'], 'p1');
      expect(state.bench.contains('p1'), isFalse);

      state.movePlayer(playerId: 'p2', slotKey: 'st');
      expect(state.lineup['st'], 'p2');
      expect(state.bench.contains('p2'), isFalse);
      expect(state.lineup.values.where((value) => value == 'p1').length, 0);
    });

    test('adds a goal and hides scorer and passer for own goal', () {
      final state = LiveGameplayState.initial(
        players: [
          const LivePlayer(id: 'p1', name: 'Alice'),
          const LivePlayer(id: 'p2', name: 'Bob'),
        ],
        formationKey: '4-4-2',
      );

      final goal = state.addGoal(
        team: 'grinta',
        minute: 23,
        type: GoalType.ownGoal,
        scorerId: 'p1',
        assisterId: 'p2',
      );

      expect(goal.team, 'grinta');
      expect(goal.scorerId, isNull);
      expect(goal.assisterId, isNull);
      expect(goal.minute, 23);
    });
  });
}
