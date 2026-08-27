import 'package:as_grinta/features/statistics/data/statistics_repository.dart';
import 'package:as_grinta/features/statistics/presentation/stats_hub_page.dart';
import 'package:flutter_test/flutter_test.dart';

PlayerStatistics _player({required StatisticsPeriod period, int assists = 0}) {
  return PlayerStatistics(
    period: period,
    periodLabel: 'Test',
    rank: 1,
    displayOrder: 1,
    playerName: 'Flo',
    profileId: null,
    isGoalkeeper: false,
    matchesPlayed: 10,
    wins: 5,
    draws: 2,
    losses: 3,
    goals: 4,
    assists: assists,
    hdm: 1,
    cleanSheets: 0,
  );
}

StatisticsPeriodData _data({
  required StatisticsPeriod period,
  required List<int> assists,
}) {
  return StatisticsPeriodData(
    period: period,
    label: 'Test',
    players: [
      for (final value in assists) _player(period: period, assists: value),
    ],
  );
}

void main() {
  test('la saison en cours montre toujours la colonne des passes décisives',
      () {
    // Première saison suivie : personne n'a encore de passe, mais c'est là
    // qu'on les saisit — la colonne doit exister.
    expect(
      statisticsShowsAssistsColumn(
        _data(period: StatisticsPeriod.current, assists: [0, 0]),
      ),
      isTrue,
    );
  });

  test('une période antérieure sans passe décisive masque la colonne', () {
    for (final period in [
      StatisticsPeriod.previous,
      StatisticsPeriod.allTime,
    ]) {
      expect(
        statisticsShowsAssistsColumn(_data(period: period, assists: [0, 0])),
        isFalse,
        reason: 'aucune passe suivie sur $period',
      );
    }
  });

  test('une période antérieure qui en porte affiche la colonne', () {
    // Ce sera le cas la saison prochaine, sans rien changer au code.
    for (final period in [
      StatisticsPeriod.previous,
      StatisticsPeriod.allTime,
    ]) {
      expect(
        statisticsShowsAssistsColumn(_data(period: period, assists: [0, 3])),
        isTrue,
        reason: 'des passes existent sur $period',
      );
    }
  });
}
