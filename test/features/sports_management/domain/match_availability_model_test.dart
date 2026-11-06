import 'package:as_grinta/features/sports_management/domain/match_availability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the private availability RPC payload', () {
    final availability = MatchAvailability.fromRpc({
      'match_id': 'match-1',
      'participant_id': 'participant-1',
      'season_player_id': 'player-1',
      'is_eligible': true,
      'availability_status': 'absent',
      'private_comment': 'Blessure légère',
      'availability_updated_at': '2026-07-20T12:00:00Z',
      'availability_state': 'open',
      'availability_opens_at': '2026-07-20T08:00:00Z',
      'kickoff_at': '2026-07-26T08:00:00Z',
      'can_respond': true,
      'composition_state': 'published',
    });

    expect(availability.status, MatchAvailabilityStatus.absent);
    expect(availability.privateComment, 'Blessure légère');
    expect(availability.canRespond, isTrue);
    expect(availability.compositionAlreadyPublished, isTrue);
  });

  test('rejects an invalid availability status', () {
    expect(
      () => MatchAvailability.fromRpc({
        'match_id': 'match-1',
        'participant_id': 'participant-1',
        'season_player_id': 'player-1',
        'is_eligible': true,
        'availability_status': 'maybe',
        'availability_state': 'open',
        'availability_opens_at': '2026-07-20T08:00:00Z',
        'kickoff_at': '2026-07-26T08:00:00Z',
        'can_respond': true,
        'composition_state': 'none',
      }),
      throwsFormatException,
    );
  });
}
