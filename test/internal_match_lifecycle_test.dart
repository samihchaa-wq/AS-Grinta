import 'package:as_grinta/core/utils/match_window.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MatchModel internalMatch(DateTime kickoff) => MatchModel(
    id: 'internal',
    seasonId: 'season',
    opponentId: '',
    kickoffAt: kickoff,
    isHome: true,
    plannedDurationMinutes: 90,
    status: 'a_venir',
    grintaScore: null,
    opponentScore: null,
    matchType: 'entre_nous',
  );

  test('un Match entre nous devient terminé exactement à son heure', () {
    final kickoff = DateTime.utc(2026, 8, 10, 17);
    final match = internalMatch(kickoff);
    final before = kickoff.subtract(const Duration(milliseconds: 1));

    expect(match.isFinishedAt(now: before), isFalse);
    expect(match.phase(now: before), MatchDisplayPhase.live);

    expect(match.isFinishedAt(now: kickoff), isTrue);
    expect(match.phase(now: kickoff), MatchDisplayPhase.past);
  });

  test('la règle automatique ne change pas les matchs classiques', () {
    final kickoff = DateTime.utc(2026, 8, 10, 17);
    final match = MatchModel(
      id: 'regular',
      seasonId: 'season',
      opponentId: 'opponent',
      kickoffAt: kickoff,
      isHome: true,
      plannedDurationMinutes: 90,
      status: 'a_venir',
      grintaScore: null,
      opponentScore: null,
      matchType: 'championnat',
    );

    expect(match.isFinishedAt(now: kickoff), isFalse);
    expect(match.phase(now: kickoff), MatchDisplayPhase.live);
  });
}
