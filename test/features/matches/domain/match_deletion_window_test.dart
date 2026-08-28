import 'package:as_grinta/features/matches/domain/match_deletion_window.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:flutter_test/flutter_test.dart';

MatchModel _matchCreatedAt(DateTime createdAt) {
  return MatchModel(
    id: 'match-id',
    seasonId: 'season-id',
    opponentId: 'opponent-id',
    kickoffAt: DateTime.utc(2026, 9, 1, 20),
    isHome: true,
    plannedDurationMinutes: 90,
    status: 'a_venir',
    grintaScore: null,
    opponentScore: null,
    createdAt: createdAt,
  );
}

void main() {
  test('la suppression est autorisée avant 24 heures', () {
    final createdAt = DateTime.utc(2026, 8, 28, 12);
    final match = _matchCreatedAt(createdAt);

    expect(
      canDeleteMatch(match, now: createdAt.add(const Duration(hours: 23, minutes: 59))),
      isTrue,
    );
  });

  test('la suppression est refusée à partir de 24 heures', () {
    final createdAt = DateTime.utc(2026, 8, 28, 12);
    final match = _matchCreatedAt(createdAt);

    expect(
      canDeleteMatch(match, now: createdAt.add(const Duration(hours: 24))),
      isFalse,
    );
  });

  test('un match sans date de création n’est pas supprimable', () {
    final match = MatchModel(
      id: 'match-id',
      seasonId: 'season-id',
      opponentId: 'opponent-id',
      kickoffAt: DateTime.utc(2026, 9, 1, 20),
      isHome: true,
      plannedDurationMinutes: 90,
      status: 'a_venir',
      grintaScore: null,
      opponentScore: null,
    );

    expect(canDeleteMatch(match, now: DateTime.utc(2026, 8, 28, 12)), isFalse);
  });
}
