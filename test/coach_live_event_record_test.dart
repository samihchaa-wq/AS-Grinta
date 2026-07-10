import 'package:as_grinta/features/coach/data/coach_live_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parse les identités temporaires des invités', () {
    final event = CoachLiveEventRecord.fromJson({
      'id': 'event-1',
      'event_type': 'goal_us',
      'minute': 42,
      'scorer_guest_id': 'guest|field|1|Alex',
      'scorer_guest_name': 'Alex',
      'assist_guest_id': 'guest|field|2|Alex',
      'assist_guest_name': 'Alex',
      'player_in_guest_id': 'guest|field|3|Sam',
      'player_in_guest_name': 'Sam',
      'player_out_guest_id': 'guest|field|4|Nico',
      'player_out_guest_name': 'Nico',
    });

    expect(event.scorerGuestId, 'guest|field|1|Alex');
    expect(event.assistGuestId, 'guest|field|2|Alex');
    expect(event.playerInGuestId, 'guest|field|3|Sam');
    expect(event.playerOutGuestId, 'guest|field|4|Nico');
  });

  test('parse les profils permanents sans identité invitée', () {
    final event = CoachLiveEventRecord.fromJson({
      'id': 'event-2',
      'event_type': 'substitution',
      'minute': 61,
      'player_in_profile_id': 'profile-in',
      'player_out_profile_id': 'profile-out',
    });

    expect(event.playerInId, 'profile-in');
    expect(event.playerOutId, 'profile-out');
    expect(event.playerInGuestId, isNull);
    expect(event.playerOutGuestId, isNull);
  });
}
