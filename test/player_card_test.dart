import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/badges/data/statistics_badge_emblems_provider.dart';
import 'package:as_grinta/features/players/data/player_card_repository.dart';
import 'package:as_grinta/features/players/presentation/player_card_link.dart';
import 'package:as_grinta/features/players/presentation/player_card_page.dart';
import 'package:as_grinta/features/statistics/data/statistics_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Fiche joueur : son adresse, le lien posé sur les noms du module
/// Statistiques et ce qu'elle affiche à partir des chiffres reçus.
void main() {
  group('adresse de la fiche', () {
    test('un joueur sans compte se retrouve par son nom et son poste', () {
      const key = (profileId: null, fullName: 'Karim Ben', isGoalkeeper: true);
      final location = playerCardLocation(key);

      expect(location, startsWith('/stats/joueur?'));
      expect(playerCardKeyFromUri(Uri.parse(location)), key);
    });

    test('un compte seul suffit (classement des pronostics)', () {
      const key = (profileId: 'p-1', fullName: '', isGoalkeeper: false);

      expect(
        playerCardKeyFromUri(Uri.parse(playerCardLocation(key))),
        key,
      );
    });

    test('une adresse sans joueur ne désigne personne', () {
      expect(playerCardKeyFromUri(Uri.parse('/stats/joueur')), isNull);
    });
  });

  group('lien sur le nom', () {
    Future<GoRouter> pumpLink(WidgetTester tester,
        {required bool scoped}) async {
      const link = PlayerCardLink(
        playerKey: (profileId: 'p-1', fullName: '', isGoalkeeper: false),
        child: Text('Karim'),
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => Scaffold(
              body: scoped
                  ? const PlayerCardLinkScope(enabled: true, child: link)
                  : link,
            ),
          ),
          GoRoute(
            path: '/stats/joueur',
            builder: (_, __) => const Text('fiche ouverte'),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      return router;
    }

    testWidgets('dans le module Statistiques, toucher le nom ouvre la fiche',
        (tester) async {
      await pumpLink(tester, scoped: true);

      await tester.tap(find.text('Karim'));
      await tester.pumpAndSettle();

      expect(find.text('fiche ouverte'), findsOneWidget);
    });

    testWidgets('ailleurs, le nom reste un simple texte', (tester) async {
      await pumpLink(tester, scoped: false);

      expect(find.byType(InkWell), findsNothing);
    });
  });

  group('page', () {
    const key = (profileId: null, fullName: 'Karim Ben', isGoalkeeper: false);

    Future<void> pumpPage(
      WidgetTester tester, {
      required Map<StatisticsPeriod, List<PlayerStatistics>> players,
      required PlayerCardDetails details,
    }) async {
      await tester.binding.setSurfaceSize(const Size(420, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            for (final period in StatisticsPeriod.values)
              statisticsPeriodProvider(period).overrideWith(
                (ref) async => StatisticsPeriodData(
                  period: period,
                  label: period.fallbackLabel,
                  players: players[period] ?? const [],
                ),
              ),
            playerCardDetailsProvider(key).overrideWith((ref) async => details),
            statisticsBadgeEmblemsProvider.overrideWith(
              (ref) async => const <String, List<StatisticsBadgeEmblemData>>{},
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const PlayerCardPage(playerKey: key),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('affiche les chiffres, le rang au club et les derniers matchs',
        (tester) async {
      await pumpPage(
        tester,
        players: {
          StatisticsPeriod.current: [
            _player('Karim Ben', played: 14, goals: 11, assists: 6, hdm: 4),
            _player('Maxime Roy', played: 12, goals: 3, assists: 8),
          ],
          StatisticsPeriod.allTime: [
            _player('Karim Ben', played: 112, goals: 60),
          ],
        },
        details: PlayerCardDetails(
          displayName: 'Karim',
          photoUrl: null,
          profileId: null,
          recentMatches: [
            _match('FC Les Lilas', 4, 1, goals: 2, motm: true),
            _match('AC Vincennes', 0, 2),
          ],
        ),
      );

      expect(find.text('KARIM'), findsOneWidget);
      expect(
        find.text('AS La Grinta · 112 matchs', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('11'), findsOneWidget);
      // Meilleur buteur du club, mais 2e passeur derrière Maxime.
      expect(find.text('1er du club'), findsWidgets);
      expect(find.text('2e du club'), findsOneWidget);
      expect(find.text('0,79'), findsOneWidget);
      expect(find.text('FC Les Lilas'), findsOneWidget);
      expect(find.text('4-1'), findsOneWidget);
      expect(find.text('HDM'), findsOneWidget);
    });

    testWidgets('une période sans match le dit au lieu d’afficher des zéros',
        (tester) async {
      await pumpPage(
        tester,
        players: {
          StatisticsPeriod.allTime: [_player('Karim Ben', played: 3)],
        },
        details: const PlayerCardDetails(
          displayName: 'Karim',
          photoUrl: null,
          profileId: null,
          recentMatches: [],
        ),
      );

      expect(find.text('Aucun match sur cette période.'), findsOneWidget);
    });

    testWidgets('un membre qui ne joue pas n’a pas de fiche', (tester) async {
      await pumpPage(
        tester,
        players: const {},
        details: const PlayerCardDetails(
          displayName: null,
          photoUrl: null,
          profileId: null,
          recentMatches: [],
        ),
      );

      expect(find.text('Pas de fiche joueur'), findsOneWidget);
    });
  });
}

PlayerStatistics _player(
  String fullName, {
  required int played,
  int goals = 0,
  int assists = 0,
  int hdm = 0,
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
      wins: played ~/ 2,
      draws: 1,
      losses: played - played ~/ 2 - 1,
      goals: goals,
      assists: assists,
      hdm: hdm,
      cleanSheets: 0,
    );

PlayerMatchLine _match(
  String opponent,
  int grinta,
  int adverse, {
  int goals = 0,
  bool motm = false,
}) =>
    PlayerMatchLine(
      matchId: opponent,
      date: DateTime(2026, 10, 4),
      opponentName: opponent,
      grintaScore: grinta,
      opponentScore: adverse,
      isHome: true,
      matchType: 'championnat',
      goals: goals,
      assists: 0,
      isManOfTheMatch: motm,
    );
