import 'package:as_grinta/features/sports_management/domain/admin_motm_dashboard.dart';
import 'package:as_grinta/features/sports_management/domain/sport_motm_vote.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parse le suivi HDM sans identité de votant', () {
    final dashboard = AdminMotmDashboard.fromJson({
      'match_id': 'match-1',
      'opponent_name': 'Readiness FC',
      'score_as_grinta': 2,
      'score_adverse': 1,
      'state': 'open',
      'opens_at': '2026-07-20T18:00:00Z',
      'closes_at': '2026-07-21T18:00:00Z',
      'finalization_version': 2,
      'eligible_voter_count': 12,
      'votes_received': 8,
      'candidate_count': 14,
      'participation_rate': 66.7,
      'notifications': {'open': true, 'reminder': false, 'results': false},
      'winners': const [],
      'actions': [
        {
          'action': 'open_motm_vote',
          'reason': 'Feuille validée',
          'actor_name': 'Admin Grinta',
          'created_at': '2026-07-20T18:00:00Z',
        },
      ],
    });

    expect(dashboard.summary.state, SportMotmVoteState.open);
    expect(dashboard.summary.eligibleVoterCount, 12);
    expect(dashboard.summary.votesReceived, 8);
    expect(dashboard.summary.participationRate, 66.7);
    expect(dashboard.openNotificationSent, isTrue);
    expect(dashboard.actions.single.actorName, 'Admin Grinta');
  });

  test('parse le contrôle de cohérence statistique', () {
    final integrity = SportStatisticsIntegrity.fromJson({
      'match_id': 'match-1',
      'finalization_version': 3,
      'attendance_ok': true,
      'goals_ok': true,
      'clean_sheets_ok': true,
      'motm_ok': false,
      'all_ok': false,
    });

    expect(integrity.finalizationVersion, 3);
    expect(integrity.attendanceOk, isTrue);
    expect(integrity.motmOk, isFalse);
    expect(integrity.allOk, isFalse);
  });
}
