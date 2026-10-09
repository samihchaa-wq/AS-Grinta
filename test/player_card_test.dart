import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/badges/data/badge_repository.dart';
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

  group('badges visibles sur la fiche d’un autre membre', () {
    test('tous les badges gagnés apparaissent, secrets compris', () {
      final badges = publicEarnedBadges(
        catalog: [
          _badge('matches_50', kind: 'tier', threshold: 50, sortOrder: 2),
          _badge('matches_100', kind: 'tier', threshold: 100, sortOrder: 3),
          _badge('traitre', kind: 'title', secret: true, sortOrder: 1),
          _badge('ballon_or', kind: 'title', sortOrder: 0),
        ],
        earnedAt: {
          'matches_50': DateTime(2026),
          'traitre': DateTime(2026),
          'ballon_or': DateTime(2026),
        },
      );

      expect(
        badges.map((b) => b.def.code),
        ['ballon_or', 'traitre', 'matches_50'],
      );
      // Le cumul réel n'est lisible que par le titulaire : un palier montre
      // son seuil, un titre aucun chiffre.
      expect(badges.last.displayValue, 50);
      expect(badges.first.displayValue, isNull);
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
            _player('Maxime Roy', played: 12, goals: 3, assists: 8, hdm: 7),
            _player('Paul Dia', played: 10, goals: 5, assists: 7, hdm: 6),
            _player('Léo Sy', played: 9, goals: 12, hdm: 5),
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
      // Ni poste ni ligne « AS La Grinta · N matchs » dans l'en-tête.
      expect(find.text('Joueur de champ'), findsNothing);
      expect(find.textContaining('AS La Grinta'), findsNothing);

      // Les six statistiques, dans l'ordre demandé, sur deux lignes de trois.
      final labels = [
        'MATCHS',
        'VICTOIRES',
        'BUTS',
        'PASSES D.',
        'HOMME DU MATCH',
        'BUTS / MATCH',
      ];
      final positions = [
        for (final label in labels) tester.getCenter(find.text(label)),
      ];
      for (final row in [positions.sublist(0, 3), positions.sublist(3)]) {
        expect(row[0].dx, lessThan(row[1].dx));
        expect(row[1].dx, lessThan(row[2].dx));
      }
      expect(positions[3].dy, greaterThan(positions[0].dy));

      // Un rang au club sous chaque statistique, et une couleur de podium :
      // 1er en matchs (or), 2e en buts derrière Léo (argent), 3e en passes
      // (bronze), 4e en HDM (blanc).
      Color colorOf(String value) =>
          tester.widget<Text>(find.text(value)).style!.color!;
      expect(colorOf('14'), const Color(0xFFFFD84A));
      expect(colorOf('11'), const Color(0xFFAEBACA));
      expect(colorOf('6'), const Color(0xFFDB9A5B));
      expect(colorOf('4'), AppTheme.textPrimary);
      expect(find.text('3e du club'), findsOneWidget);
      expect(find.text('4e du club'), findsOneWidget);
      expect(find.text('0,79'), findsOneWidget);

      expect(find.text('FC Les Lilas'), findsOneWidget);
      expect(find.text('4-1'), findsOneWidget);
      expect(find.text('👑'), findsOneWidget);
      // Joueur sans compte : pas de module Badges.
      expect(find.text('BADGES'), findsNothing);
    });

    testWidgets('une valeur nulle ne donne ni rang ni podium', (tester) async {
      await pumpPage(
        tester,
        players: {
          StatisticsPeriod.current: [
            _player('Karim Ben', played: 2, goals: 1),
            _player('Maxime Roy', played: 2, goals: 1),
          ],
        },
        details: const PlayerCardDetails(
          displayName: 'Karim',
          photoUrl: null,
          profileId: null,
          recentMatches: [],
        ),
      );

      // Personne n'a de passe ni de HDM : aucun « 1er du club » à la clé.
      final hdmTile = find.ancestor(
        of: find.text('HOMME DU MATCH'),
        matching: find.byType(Column),
      );
      expect(
        find.descendant(of: hdmTile.first, matching: find.text('–')),
        findsOneWidget,
      );
    });

    testWidgets('le module Badges liste les badges gagnés', (tester) async {
      const profileKey = (
        profileId: 'p-karim',
        fullName: 'Karim Ben',
        isGoalkeeper: false,
      );
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            for (final period in StatisticsPeriod.values)
              statisticsPeriodProvider(period).overrideWith(
                (ref) async => StatisticsPeriodData(
                  period: period,
                  label: period.fallbackLabel,
                  players: [_player('Karim Ben', played: 3)],
                ),
              ),
            playerCardDetailsProvider(profileKey).overrideWith(
              (ref) async => const PlayerCardDetails(
                displayName: 'Karim',
                photoUrl: null,
                profileId: 'p-karim',
                recentMatches: [],
              ),
            ),
            playerCardBadgesProvider('p-karim').overrideWith(
              (ref) async => [
                ArmoireBadge(
                  def: _badge('goals_10', name: 'Buteur'),
                  state: BadgeState.validated,
                ),
              ],
            ),
            statisticsBadgeEmblemsProvider.overrideWith(
              (ref) async => const <String, List<StatisticsBadgeEmblemData>>{},
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const PlayerCardPage(playerKey: profileKey),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('BADGES'), findsOneWidget);
      expect(find.text('Buteur'), findsOneWidget);
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

BadgeDef _badge(
  String code, {
  String name = 'Badge',
  String kind = 'tier',
  int? threshold,
  int sortOrder = 0,
  bool secret = false,
}) =>
    BadgeDef(
      code: code,
      name: name,
      description: '',
      emoji: '🏅',
      imageUrl: null,
      color: null,
      family: 'joueur',
      kind: kind,
      category: 'all_time',
      metric: kind == 'tier' ? 'matches_played' : null,
      threshold: threshold,
      sortOrder: sortOrder,
      secret: secret,
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
