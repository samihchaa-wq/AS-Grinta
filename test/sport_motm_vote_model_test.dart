import 'package:as_grinta/features/sports_management/domain/sport_motm_vote.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('masque les résultats pendant un scrutin ouvert', () {
    final vote = SportMotmVote.fromJson({
      'match_id': 'match-1',
      'opponent_name': 'Vote FC',
      'score_as_grinta': 2,
      'score_adverse': 1,
      'state': 'open',
      'opens_at': '2026-07-20T18:00:00Z',
      'closes_at': '2026-07-21T18:00:00Z',
      'finalization_version': 1,
      'has_voted': false,
      'can_vote': true,
      'is_eligible_voter': true,
      'total_votes': null,
      'max_votes': null,
      'candidates': [
        {
          'participant_id': 'participant-1',
          'display_name': 'Samih',
          'is_guest': false,
          'is_goalkeeper': false,
          'is_self': true,
          'can_choose': false,
          'votes_count': null,
          'is_winner': null,
        },
        {
          'participant_id': 'participant-2',
          'display_name': 'Renfort (Invité)',
          'is_guest': true,
          'is_goalkeeper': false,
          'is_self': false,
          'can_choose': true,
          'votes_count': null,
          'is_winner': null,
        },
      ],
    });

    expect(vote.state, SportMotmVoteState.open);
    expect(vote.canVote, isTrue);
    expect(vote.candidates.first.canChoose, isFalse);
    expect(vote.candidates.last.isGuest, isTrue);
    expect(vote.candidates.last.votesCount, isNull);
    expect(vote.winners, isEmpty);
  });

  test('accepte plusieurs co-HDM après clôture', () {
    final vote = SportMotmVote.fromJson({
      'match_id': 'match-1',
      'opponent_name': 'Vote FC',
      'score_as_grinta': 1,
      'score_adverse': 1,
      'state': 'closed',
      'finalization_version': 1,
      'has_voted': true,
      'can_vote': false,
      'is_eligible_voter': true,
      'total_votes': 2,
      'max_votes': 1,
      'candidates': [
        {
          'participant_id': 'participant-1',
          'display_name': 'Joueur permanent',
          'is_guest': false,
          'is_goalkeeper': false,
          'is_self': false,
          'can_choose': true,
          'votes_count': 1,
          'is_winner': true,
        },
        {
          'participant_id': 'participant-2',
          'display_name': 'Renfort (Invité)',
          'is_guest': true,
          'is_goalkeeper': false,
          'is_self': false,
          'can_choose': true,
          'votes_count': 1,
          'is_winner': true,
        },
      ],
    });

    expect(vote.isClosed, isTrue);
    expect(vote.totalVotes, 2);
    expect(vote.winners, hasLength(2));
    expect(vote.winners.last.isGuest, isTrue);
  });
}
