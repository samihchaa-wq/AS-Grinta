import 'package:as_grinta/features/sports_management/domain/sport_motm_vote.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('un candidat porte ses buts et ses passes décisives', () {
    final candidate = SportMotmCandidate.fromJson({
      'participant_id': 'p1',
      'display_name': 'Flo',
      'goals': 1,
      'assists': 2,
    });
    expect(candidate.goals, 1);
    expect(candidate.assists, 2);
  });

  test('sans passes décisives renvoyées, le compteur vaut zéro', () {
    final candidate = SportMotmCandidate.fromJson({
      'participant_id': 'p1',
      'display_name': 'Flo',
    });
    expect(candidate.assists, 0);
  });
}
