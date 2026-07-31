import 'package:as_grinta/features/match_live/domain/match_live_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MatchLiveSession stopwatch', () {
    test('elapsedAt reflects the stored value while paused', () {
      const session = MatchLiveSession(
        matchId: 'm1',
        sessionExists: true,
        state: MatchLiveState.paused,
        planPlannedDurationMinutes: 90,
        half: 1,
        elapsedSeconds: 754,
        scoreAsGrinta: 1,
        scoreAdverse: 0,
        exported: false,
        lineupRevision: 0,
      );
      final now = DateTime.now();
      expect(session.elapsedAt(now), const Duration(seconds: 754));
      // 754s = 12min34s -> minute affichée = 13 (1-indexée).
      expect(session.displayMinuteAt(now), 13);
    });

    test('elapsedAt adds the running span since running_since', () {
      final runningSince = DateTime.now().subtract(const Duration(seconds: 30));
      final session = MatchLiveSession(
        matchId: 'm1',
        sessionExists: true,
        state: MatchLiveState.running,
        planPlannedDurationMinutes: 90,
        half: 1,
        elapsedSeconds: 60,
        runningSince: runningSince,
        scoreAsGrinta: 0,
        scoreAdverse: 0,
        exported: false,
        lineupRevision: 0,
      );
      final elapsed = session.elapsedAt(DateTime.now());
      expect(elapsed.inSeconds, greaterThanOrEqualTo(90));
      expect(elapsed.inSeconds, lessThan(95));
    });

    test('isLive is true for running, paused and halftime only', () {
      for (final state in MatchLiveState.values) {
        final session = MatchLiveSession(
          matchId: 'm1',
          sessionExists: true,
          state: state,
          planPlannedDurationMinutes: 90,
          half: 1,
          elapsedSeconds: 0,
          scoreAsGrinta: 0,
          scoreAdverse: 0,
          exported: false,
          lineupRevision: 0,
        );
        final expected = state == MatchLiveState.running ||
            state == MatchLiveState.paused ||
            state == MatchLiveState.halftime;
        expect(session.isLive, expected, reason: 'state=$state');
      }
    });

    test('fromJson parses the RPC shape', () {
      final session = MatchLiveSession.fromJson({
        'match_id': 'm1',
        'session_exists': true,
        'state': 'running',
        'planned_duration_minutes': 70,
        'half': 2,
        'elapsed_seconds': 3000,
        'running_since': DateTime.now().toIso8601String(),
        'score_as_grinta': 2,
        'score_adverse': 1,
        'exported': false,
        'lineup_revision': 4,
      });
      expect(session.state, MatchLiveState.running);
      expect(session.planPlannedDurationMinutes, 70);
      expect(session.half, 2);
      expect(session.scoreAsGrinta, 2);
      expect(session.scoreAdverse, 1);
      expect(session.lineupRevision, 4);
    });
  });
}
