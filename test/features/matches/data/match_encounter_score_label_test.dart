import 'package:as_grinta/features/matches/data/match_info_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les « Dernières rencontres » écrivent le score dans l'ordre domicile –
/// extérieur, comme la fiche du match : un 2–5 à l'extérieur ne doit plus
/// apparaître en 5–2.
void main() {
  test('à domicile, AS Grinta est écrite en premier', () {
    const encounter = MatchEncounter(
      grintaScore: 5,
      opponentScore: 2,
      grintaIsHome: true,
    );
    expect(encounter.scoreLabel, '5–2');
  });

  test("à l'extérieur, l'équipe qui reçoit est écrite en premier", () {
    const encounter = MatchEncounter(
      grintaScore: 5,
      opponentScore: 2,
      grintaIsHome: false,
    );
    expect(encounter.scoreLabel, '2–5');
  });

  test('sans information sur le lieu, AS Grinta reste en premier', () {
    const encounter = MatchEncounter(grintaScore: 1, opponentScore: 3);
    expect(encounter.scoreLabel, '1–3');
  });
}
