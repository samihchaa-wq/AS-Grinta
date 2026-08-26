import 'package:as_grinta/features/matches/data/completed_match_effectif_repository.dart';
import 'package:flutter_test/flutter_test.dart';

// Ces tests verrouillent la séparation Présents / Absents du module Effectif.
void main() {
  test('l effectif final sépare présents absents et invités', () {
    final effectif = CompletedMatchEffectif.fromRpc({
      'match_id': 'match-1',
      'players': [
        {'display_name': 'Zed', 'presence_status': 'present', 'is_guest': true},
        {
          'display_name': 'Ali',
          'presence_status': 'present',
          'is_guest': false,
        },
        {
          'display_name': 'Mehdi',
          'presence_status': 'absent',
          'is_guest': false,
        },
        {
          'display_name': 'Ignoré',
          'presence_status': 'pending',
          'is_guest': false,
        },
      ],
    });

    expect(effectif.present.map((player) => player.displayName), [
      'Ali',
      'Zed',
    ]);
    expect(effectif.present.last.isGuest, isTrue);
    expect(effectif.absent.map((player) => player.displayName), ['Mehdi']);
  });

  test('une archive peut construire un effectif final à partir des noms', () {
    final effectif = CompletedMatchEffectif.fromNames(
      presentNames: ['Samih', 'Aki'],
      absentNames: ['Flo'],
    );

    expect(effectif.present.map((player) => player.displayName), [
      'Aki',
      'Samih',
    ]);
    expect(effectif.absent.single.displayName, 'Flo');
  });
}
