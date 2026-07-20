import 'package:as_grinta/features/sports_management/domain/sport_match_finalization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses permanent and guest final statistics', () {
    final result = SportMatchFinalization.fromRpc({
      'match_id': 'match-1',
      'opponent_name': 'Test FC',
      'kickoff_at': '2026-07-20T18:00:00Z',
      'match_status': 'termine',
      'is_validated': true,
      'version': 2,
      'score_as_grinta': 3,
      'score_adverse': 1,
      'composition_version': 1,
      'presence_state': 'confirmed',
      'vote_state': 'draft',
      'participants': [
        {
          'participant_id': 'participant-1',
          'season_player_id': 'player-1',
          'display_name': 'Alex Permanent',
          'is_guest': false,
          'is_goalkeeper': false,
          'planned_zone': 'field',
          'present': true,
          'final_selection_status': 'starter',
          'goals': 2,
          'clean_sheet': false,
        },
        {
          'participant_id': 'participant-2',
          'guest_player_id': 'guest-1',
          'display_name': 'Sam Invité (Invité)',
          'is_guest': true,
          'is_goalkeeper': false,
          'planned_zone': 'bench',
          'present': true,
          'final_selection_status': 'substitute',
          'goals': 1,
          'clean_sheet': false,
        },
      ],
    });

    expect(result.version, 2);
    expect(result.presentCount, 2);
    expect(result.starterCount, 1);
    expect(result.substituteCount, 1);
    expect(result.guestPresentCount, 1);
    expect(result.attributedGoals, 3);
    expect(result.participants.last.isGuest, isTrue);
  });

  test('marking a participant absent clears all match statistics', () {
    const participant = SportFinalParticipant(
      participantId: 'participant-1',
      seasonPlayerId: 'player-1',
      displayName: 'Alex',
      isGuest: false,
      isGoalkeeper: true,
      plannedZone: 'field',
      present: true,
      selectionStatus: SportFinalSelectionStatus.starter,
      goals: 1,
      cleanSheet: true,
    );

    final absent = participant.copyWith(present: false);

    expect(absent.present, isFalse);
    expect(absent.selectionStatus, SportFinalSelectionStatus.notSelected);
    expect(absent.goals, 0);
    expect(absent.cleanSheet, isFalse);
    expect(absent.toRpcJson(), {
      'participant_id': 'participant-1',
      'present': false,
      'final_selection_status': 'not_selected',
      'goals': 0,
      'clean_sheet': false,
    });
  });
}
