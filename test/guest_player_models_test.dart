import 'package:as_grinta/features/sports_management/domain/guest_player_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses active and archived reusable guests', () {
    final catalog = GuestCatalog.fromRpc({
      'guests': [
        {
          'guest_player_id': 'guest-1',
          'first_name': 'Alex',
          'last_name': 'Gardien',
          'display_name': 'Alex Gardien (Invité)',
          'is_goalkeeper': true,
          'is_reusable': true,
        },
        {
          'guest_player_id': 'guest-2',
          'first_name': 'Sam',
          'last_name': null,
          'display_name': 'Sam (Invité)',
          'is_goalkeeper': false,
          'is_reusable': false,
          'archived_at': '2026-07-20T18:00:00Z',
        },
      ],
    });

    expect(catalog.guests, hasLength(2));
    expect(catalog.active.single.displayName, 'Alex Gardien (Invité)');
    expect(catalog.active.single.isGoalkeeper, isTrue);
    expect(catalog.archived.single.id, 'guest-2');
    expect(catalog.archived.single.archivedAt, isNotNull);
  });

  test('parses an invited participant attached to a match', () {
    final matchGuests = MatchGuests.fromRpc({
      'match_id': 'match-1',
      'guests': [
        {
          'participant_id': 'participant-1',
          'guest_player_id': 'guest-1',
          'first_name': 'Alex',
          'last_name': 'Gardien',
          'display_name': 'Alex Gardien (Invité)',
          'is_goalkeeper': true,
          'is_reusable': true,
          'selection_status': 'starter',
        },
      ],
    });

    expect(matchGuests.matchId, 'match-1');
    expect(matchGuests.guests.single.participantId, 'participant-1');
    expect(matchGuests.guests.single.selectionStatus, 'starter');
    expect(matchGuests.guests.single.isGoalkeeper, isTrue);
  });
}
