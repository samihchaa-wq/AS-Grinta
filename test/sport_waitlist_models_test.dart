import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the permanent waitlist attendance snapshot', () {
    final waitlist = SportWaitlist.fromRpc({
      'season_id': 'season-1',
      'season_name': '2026-2027',
      'entries': [
        {
          'season_player_id': 'player-1',
          'first_name': 'Alice',
          'last_name': 'Grinta',
          'position': 1,
          'previous_season_attendance_count': 4,
          'previous_season_match_count': 12,
          'source': 'previous_season_attendance',
        },
      ],
    });

    expect(waitlist.seasonId, 'season-1');
    expect(waitlist.entries.single.displayName, 'Alice Grinta');
    expect(waitlist.entries.single.previousSeasonAttendanceCount, 4);
    expect(waitlist.entries.single.previousSeasonMatchCount, 12);
  });

  test('keeps convocation and turn consumption independent', () {
    final snapshot = MatchConvocations.fromRpc({
      'match_id': 'match-1',
      'opponent_name': 'Positive',
      'kickoff_at': '2026-07-25T19:00:00Z',
      'season_id': 'season-1',
      'squad_size_limit': 14,
      'convocation_state': 'published',
      'convocation_version': 3,
      'late_withdrawal_cutoff_at': '2026-07-24T10:00:00Z',
      'available_count': 15,
      'convoked_count': 14,
      'not_convoked_count': 1,
      'players': [
        {
          'participant_id': 'participant-1',
          'season_player_id': 'player-1',
          'first_name': 'Samih',
          'last_name': 'Grinta',
          'availability_status': 'available',
          'convocation_status': 'convoked',
          'manual_override': true,
          'waitlist_position': 1,
          'recommended_not_convoked': false,
          'turn_should_consume': true,
          'turn_state': 'pending',
          'promoted_after_withdrawal_at': null,
        },
      ],
    });

    final player = snapshot.players.single;
    expect(player.isConvoked, isTrue);
    expect(player.turnShouldConsume, isTrue);
    expect(player.turnState, WaitlistTurnState.pending);
    expect(snapshot.isPublished, isTrue);
    expect(snapshot.isOverLimit, isFalse);
  });

  test('parses an early promoted player with a waived turn', () {
    final player = ConvocationPlayer.fromJson({
      'participant_id': 'participant-2',
      'season_player_id': 'player-2',
      'first_name': 'Luka',
      'last_name': 'Grinta',
      'availability_status': 'available',
      'convocation_status': 'convoked',
      'manual_override': true,
      'waitlist_position': 2,
      'recommended_not_convoked': false,
      'turn_should_consume': false,
      'turn_state': 'waived',
      'promoted_after_withdrawal_at': '2026-07-23T09:00:00Z',
    });

    expect(player.isConvoked, isTrue);
    expect(player.turnShouldConsume, isFalse);
    expect(player.turnState, WaitlistTurnState.waived);
    expect(player.promotedAfterWithdrawalAt, isNotNull);
  });
}
