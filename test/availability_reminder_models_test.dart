import 'package:as_grinta/features/sports_management/domain/availability_reminder_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AvailabilityReminderSummary', () {
    test('parses reminder counts and player cooldowns', () {
      final summary = AvailabilityReminderSummary.fromRpc({
        'match_id': 'match-1',
        'availability_state': 'open',
        'no_response_count': 2,
        'open_sent_count': 14,
        'j3_sent_count': 4,
        'j1_sent_count': 2,
        'last_manual_at': '2026-07-20T14:00:00Z',
        'can_remind': true,
        'players': [
          {
            'season_player_id': 'player-1',
            'last_reminder_at': '2026-07-20T14:00:00Z',
            'manual_cooldown_until': '2026-07-20T14:10:00Z',
          },
        ],
      });

      expect(summary.matchId, 'match-1');
      expect(summary.noResponseCount, 2);
      expect(summary.openSentCount, 14);
      expect(summary.j3SentCount, 4);
      expect(summary.j1SentCount, 2);
      expect(summary.canRemind, isTrue);
      expect(summary.playerFor('player-1'), isNotNull);
      expect(
        summary
            .playerFor('player-1')!
            .isInCooldownAt(DateTime.parse('2026-07-20T14:05:00Z')),
        isTrue,
      );
      expect(
        summary
            .playerFor('player-1')!
            .isInCooldownAt(DateTime.parse('2026-07-20T14:10:00Z')),
        isFalse,
      );
    });

    test('uses safe defaults when optional values are absent', () {
      final summary = AvailabilityReminderSummary.fromRpc({
        'match_id': 'match-2',
      });

      expect(summary.availabilityState, 'pending');
      expect(summary.noResponseCount, 0);
      expect(summary.canRemind, isFalse);
      expect(summary.players, isEmpty);
      expect(summary.lastManualAt, isNull);
    });
  });

  test('AvailabilityReminderResult parses server counters', () {
    final result = AvailabilityReminderResult.fromRpc({
      'target_count': 5,
      'created_count': 3,
      'skipped_recent_count': 2,
    });

    expect(result.targetCount, 5);
    expect(result.createdCount, 3);
    expect(result.skippedRecentCount, 2);
  });
}
