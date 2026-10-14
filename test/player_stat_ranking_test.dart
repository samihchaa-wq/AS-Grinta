import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/badges/data/statistics_badge_emblems_provider.dart';
import 'package:as_grinta/features/players/data/player_card_repository.dart';
import 'package:as_grinta/features/players/data/player_stat_ranking.dart';
import 'package:as_grinta/features/players/presentation/player_card_link.dart';
import 'package:as_grinta/features/players/presentation/player_card_page.dart';
import 'package:as_grinta/features/players/presentation/player_stat_ranking_page.dart';
import 'package:as_grinta/features/statistics/data/statistics_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Classement complet d'une statistique, ouvert depuis une case de la fiche
/// joueur.
void main() {
  group('classement', () {
    test('tout l’effectif, zéros compris, ex aequo au même rang', () {
      final entries = rankPlayersOnStat(
        [
          _player('Paul Dia', played: 4, goals: 3),
          _player('Karim Ben', played: 4, goals: 7),
          _player('Léo Sy', played: 2),
          _player('Ali Ka', played: 3, goals: 3),
        ],
        PlayerStat.goals,
        minMatches: 0,
      );

      expect(
        entries.map((e) => (e.player.playerName, e.rank)),
        [('Karim', 1), ('Ali', 2), ('Paul', 2), ('Léo', 4)],
      );
    });

    test(
        'sur une moyenne, les joueurs sous le seuil suivent, sans rang, '
        'et ne prennent pas la tête', () {
      final entries = rankPlayersOnStat(
        [
          _player('Karim Ben', played: 10, wins: 6),
          _player('Steve Lo', played: 1, wins: 1),
          _player('Paul Dia', played: 8, wins: 6),
        ],
        PlayerStat.winRate,
        minMatches: 5,
      );

      expect(
        entries.map((e) => (e.player.playerName, e.rank)),
        [('Paul', 1), ('Karim', 2), ('Steve', null)],
      );
    });

    test('les valeurs affichées reprennent celles de la fiche', () {
      final p = _player('Karim Ben', played: 4, goals: 7, wins: 3);
      expect(PlayerStat.winRate.display(p), '75 %');
      expect(PlayerStat.goalsPerMatch.display(p), '1,75');
      expect(PlayerStat.goals.display(p), '7');
      expect(
        PlayerStat.goalsPerMatch.display(_player('Léo Sy', played: 0)),
        '–',
      );
    });

    test('l’adresse garde la statistique, la période et le joueur', () {
      const key = (profileId: 'p-1', fullName: 'Karim Ben', isGoalkeeper: true);
      final uri = Uri.parse(
        playerStatRankingLocation(
          key: key,
          stat: PlayerStat.goalsPerMatch,
          period: StatisticsPeriod.allTime,
        ),
      );

      expect(uri.path, '/stats/joueur/classement');
      expect(PlayerStat.fromSlug(uri.queryParameters['stat']),
          PlayerStat.goalsPerMatch);
      expect(statisticsPeriodFromKey(uri.queryParameters['periode']),
          StatisticsPeriod.allTime);
      expect(playerCardKeyFromUri(uri), key);
    });
  });

  group('page', () {
    const karim = (profileId: null, fullName: 'Karim Ben', isGoalkeeper: false);

    List<Override> overrides(List<PlayerStatistics> players) => [
          for (final period in StatisticsPeriod.values)
            statisticsPeriodProvider(period).overrideWith(
              (ref) async => StatisticsPeriodData(
                period: period,
                label: period.fallbackLabel,
                players: period == StatisticsPeriod.current ? players : [],
              ),
            ),
          teamStatisticsPeriodProvider(StatisticsPeriod.current)
              .overrideWith((ref) async => throw StateError('hors test')),
          playerCardDetailsProvider(karim).overrideWith(
            (ref) async => const PlayerCardDetails(
              firstName: 'Karim',
              photoUrl: null,
              profileId: null,
              recentMatches: [],
            ),
          ),
          statisticsBadgeEmblemsProvider.overrideWith(
            (ref) async => const <String, List<StatisticsBadgeEmblemData>>{},
          ),
        ];

    final squad = [
      _player('Karim Ben', played: 10, goals: 5, wins: 6),
      _player('Steve Lo', played: 1, goals: 1, wins: 1),
      _player('Paul Dia', played: 8, goals: 9, wins: 6),
    ];

    Future<void> pumpRanking(WidgetTester tester, PlayerStat stat) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(squad),
          child: MaterialApp(
            theme: AppTheme.dark,
            home: PlayerStatRankingPage(
              stat: stat,
              initialPeriod: StatisticsPeriod.current,
              playerKey: karim,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('rang, nom, statistique puis matchs joués', (tester) async {
      await pumpRanking(tester, PlayerStat.goals);

      expect(find.text('B'), findsOneWidget);
      expect(find.text('J'), findsOneWidget);
      final paul = tester.getCenter(find.text('Paul'));
      final karimRow = tester.getCenter(find.text('Karim'));
      expect(paul.dy, lessThan(karimRow.dy));
      // La ligne de Paul : 1er, 9 buts, 8 matchs.
      expect(tester.getCenter(find.text('9')).dy, closeTo(paul.dy, 4));
      expect(tester.getCenter(find.text('8')).dy, closeTo(paul.dy, 4));
    });

    testWidgets('le classement des matchs n’a que trois colonnes',
        (tester) async {
      await pumpRanking(tester, PlayerStat.matches);

      expect(find.text('J'), findsOneWidget);
      expect(find.text('B'), findsNothing);
      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('sur une moyenne, les joueurs trop peu présents sont à part',
        (tester) async {
      await pumpRanking(tester, PlayerStat.winRate);

      final separator = find.text('Moins de 5 matchs');
      expect(separator, findsOneWidget);
      expect(
        tester.getCenter(find.text('Steve')).dy,
        greaterThan(tester.getCenter(separator).dy),
      );
    });

    testWidgets(
        'toucher une case de la fiche ouvre le classement, '
        'la flèche retour y ramène', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const PlayerCardPage(playerKey: karim),
          ),
          GoRoute(
            path: '/stats/joueur/classement',
            builder: (_, state) => PlayerStatRankingPage(
              stat: PlayerStat.fromSlug(state.uri.queryParameters['stat']),
              initialPeriod: statisticsPeriodFromKey(
                state.uri.queryParameters['periode'],
              ),
              playerKey: playerCardKeyFromUri(state.uri),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(squad),
          child: MaterialApp.router(
            theme: AppTheme.dark,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('BUTS'));
      await tester.pumpAndSettle();
      expect(find.text('Paul'), findsOneWidget);
      expect(find.text('BUTS'), findsNothing);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('BUTS'), findsOneWidget);
    });
  });
}

PlayerStatistics _player(
  String fullName, {
  required int played,
  int goals = 0,
  int? wins,
}) =>
    PlayerStatistics(
      period: StatisticsPeriod.current,
      periodLabel: 'Saison actuelle',
      rank: 1,
      displayOrder: 1,
      playerName: fullName.split(' ').first,
      fullName: fullName,
      profileId: null,
      isGoalkeeper: false,
      matchesPlayed: played,
      wins: wins ?? 0,
      draws: 0,
      losses: played - (wins ?? 0),
      goals: goals,
      assists: 0,
      hdm: 0,
      cleanSheets: 0,
    );
