import 'package:as_grinta/features/match_live/domain/match_live_add_player_options.dart';
import 'package:as_grinta/features/match_live/domain/match_live_event.dart';
import 'package:as_grinta/features/match_live/domain/match_live_state_bundle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la composition Live affiche seulement le prénom des invités', () {
    final bundle = MatchLiveStateBundle.fromRpc({
      'match_id': 'match-1',
      'session_exists': true,
      'state': 'running',
      'lineup': {
        'match_id': 'match-1',
        'formation_code': '4-2-1-3',
        'status': 'published',
        'version': 1,
        'entries': [
          {
            'participant_id': 'guest-participant',
            'season_player_id': null,
            'guest_player_id': 'guest-1',
            'display_name': 'Roman Yassinski (Invité)',
            'is_guest': true,
            'is_goalkeeper': false,
            'zone': 'field',
            'sort_order': 0,
          },
          {
            'participant_id': 'regular-participant',
            'season_player_id': 'season-player-1',
            'display_name': 'François Dupont',
            'is_guest': false,
            'is_goalkeeper': false,
            'zone': 'bench',
            'sort_order': 0,
          },
        ],
      },
      'events': const [],
      'substitute_counts': const <String, int>{},
    });

    final entries = bundle.lineup!.entries;
    expect(entries[0].displayName, 'Roman');
    expect(entries[1].displayName, 'François Dupont');
  });

  test('la liste d’ajout affiche seulement le prénom des invités', () {
    final options = MatchLiveAddPlayerOptions.fromRpc({
      'match_id': 'match-1',
      'session_state': 'running',
      'roster': [
        {
          'participant_id': 'regular-participant',
          'season_player_id': 'season-player-1',
          'display_name': 'François Dupont',
          'is_guest': false,
        },
      ],
      'guests': [
        {
          'guest_player_id': 'guest-1',
          'display_name': 'Roman Yassinski (Invité)',
          'is_guest': true,
        },
      ],
    });

    expect(options.guests.single.displayName, 'Roman');
    expect(options.roster.single.displayName, 'François Dupont');
  });

  test('le journal Live raccourcit uniquement les noms d’invités', () {
    final event = MatchLiveEvent.fromJson({
      'id': 'event-1',
      'event_type': 'substitution',
      'minute': 20,
      'half': 1,
      'scorer_name': 'Roman Yassinski (Invité)',
      'assist_name': 'François Dupont',
      'player_in_name': 'Roman Yassinski (Invité)',
      'player_out_name': 'François Dupont',
    });

    expect(event.scorerName, 'Roman');
    expect(event.assistName, 'François Dupont');
    expect(event.playerInName, 'Roman');
    expect(event.playerOutName, 'François Dupont');
  });
}
