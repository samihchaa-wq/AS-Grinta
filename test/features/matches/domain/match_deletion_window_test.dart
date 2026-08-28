import 'package:as_grinta/features/matches/domain/match_deletion_window.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:flutter_test/flutter_test.dart';

MatchModel _matchAt(DateTime kickoffAt) {
  return MatchModel(
    id: 'match-id',
    seasonId: 'season-id',
    opponentId: 'opponent-id',
    kickoffAt: kickoffAt,
    isHome: true,
    plannedDurationMinutes: 90,
    status: 'a_venir',
    grintaScore: null,
    opponentScore: null,
    createdAt: DateTime.utc(2026, 8, 1),
  );
}

void main() {
  test(
    'un match à venir reste supprimable même créé depuis plus de 24 heures',
    () {
      final kickoffAt = DateTime.utc(2026, 9, 1, 20);
      final match = _matchAt(kickoffAt);

      expect(
        canDeleteMatch(match, now: DateTime.utc(2026, 8, 29, 0, 45)),
        isTrue,
      );
    },
  );

  test(
    'la suppression est autorisée pendant les 24 heures après le coup d’envoi',
    () {
      final kickoffAt = DateTime.utc(2026, 8, 28, 21, 32);
      final match = _matchAt(kickoffAt);

      expect(
        canDeleteMatch(
          match,
          now: kickoffAt.add(const Duration(hours: 23, minutes: 59)),
        ),
        isTrue,
      );
    },
  );

  test(
    'la suppression est refusée à partir de 24 heures après le coup d’envoi',
    () {
      final kickoffAt = DateTime.utc(2026, 8, 28, 21, 32);
      final match = _matchAt(kickoffAt);

      expect(
        canDeleteMatch(match, now: kickoffAt.add(const Duration(hours: 24))),
        isFalse,
      );
    },
  );
}
