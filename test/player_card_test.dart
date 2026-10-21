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

  group('seuil de classement des moyennes', () {
    List<PlayerStatistics> squad(int mostPlayed) =>
        [_player('Karim Ben', played: mostPlayed)];

    test('toutes saisons : 20 matchs', () {
      expect(
        averageRankingMinMatches(
          StatisticsPeriod.allTime,
          teamMatches: null,
          players: squad(40),
        ),
        20,
      );
    });

    test('saison précédente : 5 matchs', () {
      expect(
        averageRankingMinMatches(
          StatisticsPeriod.previous,
          teamMatches: null,
          players: squad(20),
        ),
        5,
      );
    });

    test('saison en cours : aucun seuil jusqu’à 5 matchs d’équipe', () {
      expect(
        averageRankingMinMatches(
          StatisticsPeriod.current,
          teamMatches: 5,
          players: squad(5),
        ),
        0,
      );
      expect(
        averageRankingMinMatches(
          StatisticsPeriod.current,
          teamMatches: 6,
          players: squad(3),
        ),
        5,
      );
    });

    test('saison en cours : le joueur le plus présent sert de minimum', () {
      expect(
        averageRankingMinMatches(
          StatisticsPeriod.current,
          teamMatches: null,
          players: squad(7),
        ),
        5,
      );
    });
  });

  group('page', () {
    const key = (profileId: null, fullName: 'Karim Ben', isGoalkeeper: false);

    Future<void> pumpPage(
      WidgetTester tester, {
      required Map<StatisticsPeriod, List<PlayerStatistics>> players,
      required PlayerCardDetails details,
      Future<List<PlayerSeasonStats>> Function()? seasons,
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
            playerSeasonStatsProvider(key).overrideWith(
              (ref) => seasons?.call() ?? Future.value(const []),
            ),
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
          firstName: 'Karim',
          photoUrl: null,
          profileId: null,
          recentMatches: [
            _match('FC Les Lilas', 4, 1, goals: 2, motm: true),
            _match('AC Vincennes', 0, 2),
            // Gagné 5-0 à l'extérieur : l'équipe qui reçoit est écrite d'abord.
            _match('Toulouse Métropole', 5, 0, isHome: false),
          ],
        ),
      );

      expect(find.text('Karim'), findsOneWidget);
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
      expect(find.text('0-5'), findsOneWidget);
      expect(find.text('5-0'), findsNothing);
      expect(find.text('👑'), findsOneWidget);
      // Joueur sans compte : pas de module Badges.
      expect(find.text('BADGES'), findsNothing);
    });

    testWidgets('toucher un match ouvre sa fiche, le retour ramène ici',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const PlayerCardPage(playerKey: key),
          ),
          GoRoute(
            path: '/matches/:matchId',
            builder: (_, state) => Scaffold(
              appBar: AppBar(),
              body: Text('fiche ${state.pathParameters['matchId']}'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
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
            playerCardDetailsProvider(key).overrideWith(
              (ref) async => PlayerCardDetails(
                firstName: 'Karim',
                photoUrl: null,
                profileId: null,
                recentMatches: [_match('m-42', 2, 1)],
              ),
            ),
            statisticsBadgeEmblemsProvider.overrideWith(
              (ref) async => const <String, List<StatisticsBadgeEmblemData>>{},
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.dark,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('m-42'));
      await tester.pumpAndSettle();
      expect(find.text('fiche m-42'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('DERNIERS MATCHS'), findsOneWidget);
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
          firstName: 'Karim',
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
                firstName: 'Karim',
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
          firstName: 'Karim',
          photoUrl: null,
          profileId: null,
          recentMatches: [],
        ),
      );

      expect(find.text('Aucun match sur cette période.'), findsOneWidget);
    });

    testWidgets(
        'l’en-tête montre le vrai prénom, puis le surnom entre guillemets',
        (tester) async {
      await pumpPage(
        tester,
        players: {
          StatisticsPeriod.allTime: [_player('Karim Ben', played: 3)],
        },
        details: const PlayerCardDetails(
          firstName: 'FRANÇOIS',
          nickname: 'Ibra',
          photoUrl: null,
          profileId: null,
          recentMatches: [],
        ),
      );

      expect(find.text('François'), findsOneWidget);
      expect(find.text('SURNOM'), findsNothing);
      expect(find.text('«\u00A0Ibra\u00A0»'), findsOneWidget);
    });

    testWidgets(
        'un joueur trop peu présent n’est pas classé sur les moyennes, '
        'et ne prend pas la tête aux autres', (tester) async {
      await pumpPage(
        tester,
        players: {
          StatisticsPeriod.current: [
            _player('Karim Ben', played: 10, goals: 5, wins: 6),
            // Un seul match, gagné, un but : 100 % et 1 but par match.
            _player('Steve Lo', played: 1, goals: 1, wins: 1),
          ],
        },
        details: const PlayerCardDetails(
          firstName: 'Karim',
          photoUrl: null,
          profileId: null,
          recentMatches: [],
        ),
      );

      String rankLine(String label) {
        final tile = find
            .ancestor(of: find.text(label), matching: find.byType(Column))
            .first;
        return tester
            .widgetList<Text>(
              find.descendant(of: tile, matching: find.byType(Text)),
            )
            .last
            .data!;
      }

      expect(rankLine('VICTOIRES'), '1er du club');
      expect(rankLine('BUTS / MATCH'), '1er du club');
    });

    testWidgets('sous le seuil de matchs, les moyennes affichent N/A',
        (tester) async {
      await pumpPage(
        tester,
        players: {
          StatisticsPeriod.current: [
            _player('Karim Ben', played: 1, goals: 1, wins: 1),
            _player('Steve Lo', played: 10, goals: 5, wins: 6),
          ],
        },
        details: const PlayerCardDetails(
          firstName: 'Karim',
          photoUrl: null,
          profileId: null,
          recentMatches: [],
        ),
      );

      // La valeur reste affichée ; seul le rang devient N/A.
      expect(find.text('100 %'), findsOneWidget);
      expect(find.text('N/A'), findsNWidgets(2));
    });

    testWidgets('un membre qui ne joue pas n’a pas de fiche', (tester) async {
      await pumpPage(
        tester,
        players: const {},
        details: const PlayerCardDetails(
          firstName: null,
          photoUrl: null,
          profileId: null,
          recentMatches: [],
        ),
      );

      expect(find.text('Pas de fiche joueur'), findsOneWidget);
    });

    group('évolution par saison', () {
      const details = PlayerCardDetails(
        firstName: 'Karim',
        photoUrl: null,
        profileId: null,
        recentMatches: [],
      );
      final career = {
        StatisticsPeriod.current: [_player('Karim Ben', played: 4)],
        StatisticsPeriod.allTime: [_player('Karim Ben', played: 9, goals: 6)],
      };

      Color colorOf(WidgetTester tester, String value) =>
          tester.widget<Text>(find.text(value)).style!.color!;

      testWidgets(
          'dans Carrière, une barre par saison : la meilleure en or, '
          'la saison en cours signalée', (tester) async {
        await pumpPage(
          tester,
          players: career,
          details: details,
          seasons: () async => withMissedSeasons([
            _season('2021-2022', played: 30, wins: 19, goals: 40, hdm: 12),
            _season('2023-2024', played: 29, wins: 22, goals: 53, hdm: 10),
            _season('2024-2025', played: 31, wins: 24, goals: 45, hdm: 7),
            _season(
              '2026-2027',
              played: 4,
              wins: 3,
              goals: 7,
              hdm: 1,
              current: true,
            ),
          ]),
        );

        // Une seule saison par onglet : pas d'évolution hors Carrière.
        expect(find.text('ÉVOLUTION'), findsNothing);

        await tester.tap(find.text('Carrière'));
        await tester.pumpAndSettle();

        expect(find.text('ÉVOLUTION'), findsOneWidget);
        // Les saisons manquées apparaissent, vides, à leur place.
        final xs = [
          for (final label in [
            '21-22',
            '22-23',
            '23-24',
            '24-25',
            '25-26',
            '26-27',
          ])
            tester.getCenter(find.text(label)).dx,
        ];
        expect(xs, orderedEquals([...xs]..sort()));
        expect(xs.toSet(), hasLength(6));

        // Un joueur de champ voit d'abord ses buts.
        expect(colorOf(tester, '53'), const Color(0xFFFFD84A));
        expect(colorOf(tester, '40'), AppTheme.textSecondary);
        expect(find.text('7'), findsOneWidget);
        expect(find.text('Saison 2026-2027 en cours.'), findsOneWidget);

        await tester.tap(find.text('HDM'));
        await tester.pumpAndSettle();
        expect(colorOf(tester, '12'), const Color(0xFFFFD84A));
        expect(find.text('53'), findsNothing);

        // Une moyenne sur moins de cinq matchs ne prend pas l'or ; une saison
        // sans match n'a pas de valeur.
        await tester.tap(find.text('% Victoires'));
        await tester.pumpAndSettle();
        expect(colorOf(tester, '77 %'), const Color(0xFFFFD84A));
        expect(colorOf(tester, '76 %'), AppTheme.textSecondary);
        expect(colorOf(tester, '75 %'), AppTheme.textSecondary);
        final card = find
            .ancestor(
              of: find.text('ÉVOLUTION'),
              matching: find.byType(Container),
            )
            .first;
        expect(
          find.descendant(of: card, matching: find.text('–')),
          findsNWidgets(2),
        );
      });

      testWidgets(
          'une moyenne sur deux matchs ne fait pas la meilleure saison, '
          'un total si', (tester) async {
        await pumpPage(
          tester,
          players: career,
          details: details,
          seasons: () async => [
            _season('2019-2020', played: 2, wins: 2, goals: 4),
            _season('2020-2021', played: 20, wins: 10, goals: 30),
            _season('2021-2022', played: 25, wins: 10, goals: 40),
          ],
        );
        await tester.tap(find.text('Carrière'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('% Victoires'));
        await tester.pumpAndSettle();
        expect(colorOf(tester, '100 %'), AppTheme.textSecondary);
        expect(colorOf(tester, '50 %'), const Color(0xFFFFD84A));

        await tester.tap(find.text('Buts / match'));
        await tester.pumpAndSettle();
        expect(colorOf(tester, '2,00'), AppTheme.textSecondary);
        expect(colorOf(tester, '1,60'), const Color(0xFFFFD84A));

        await tester.tap(find.text('Matchs'));
        await tester.pumpAndSettle();
        expect(colorOf(tester, '25'), const Color(0xFFFFD84A));
      });

      testWidgets('beaucoup de saisons : la plus récente reste visible',
          (tester) async {
        await pumpPage(
          tester,
          players: career,
          details: details,
          seasons: () async => [
            for (var year = 2013; year <= 2026; year++)
              _season('$year-${year + 1}', played: 20, wins: 10, goals: 5),
          ],
        );
        await tester.tap(find.text('Carrière'));
        await tester.pumpAndSettle();

        expect(find.text('26-27').hitTestable(), findsOneWidget);
        expect(find.text('13-14').hitTestable(), findsNothing);
      });

      testWidgets('une seule saison, ou un détail illisible : pas de graphique',
          (tester) async {
        await pumpPage(
          tester,
          players: career,
          details: details,
          seasons: () async => [
            _season('2025-2026', played: 20, wins: 10, goals: 5),
          ],
        );
        await tester.tap(find.text('Carrière'));
        await tester.pumpAndSettle();
        expect(find.text('ÉVOLUTION'), findsNothing);

        await pumpPage(
          tester,
          players: career,
          details: details,
          seasons: () async => throw Exception('fonction absente'),
        );
        await tester.tap(find.text('Carrière'));
        await tester.pumpAndSettle();
        expect(find.text('ÉVOLUTION'), findsNothing);
        // Le reste de la fiche s'affiche normalement.
        expect(find.text('BILAN'), findsOneWidget);
      });
    });
  });

  group('saisons manquées', () {
    test('une saison sans match entre deux autres apparaît, vide', () {
      final seasons = withMissedSeasons([
        _season('2019-2020', played: 3, wins: 1, goals: 1),
        _season('2022-2023', played: 2, wins: 2, goals: 0),
      ]);
      expect(
        [for (final s in seasons) s.seasonName],
        ['2019-2020', '2020-2021', '2021-2022', '2022-2023'],
      );
      expect(seasons[1].matchesPlayed, 0);
      expect(seasons[3].matchesPlayed, 2);
    });

    test('un nom de saison inattendu laisse la liste telle quelle', () {
      final seasons = [
        _season('2019-2020', played: 3, wins: 1, goals: 1),
        _season('Saison test', played: 2, wins: 2, goals: 0),
      ];
      expect(withMissedSeasons(seasons), same(seasons));
    });
  });
}

PlayerStatistics _player(
  String fullName, {
  required int played,
  int goals = 0,
  int assists = 0,
  int hdm = 0,
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
      wins: wins ?? played ~/ 2,
      draws: wins == null ? 1 : 0,
      losses: wins == null ? played - played ~/ 2 - 1 : played - wins,
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
  bool isHome = true,
}) =>
    PlayerMatchLine(
      matchId: opponent,
      date: DateTime(2026, 10, 4),
      opponentName: opponent,
      grintaScore: grinta,
      opponentScore: adverse,
      isHome: isHome,
      matchType: 'championnat',
      goals: goals,
      assists: 0,
      isManOfTheMatch: motm,
    );

PlayerSeasonStats _season(
  String name, {
  required int played,
  required int wins,
  required int goals,
  int hdm = 0,
  bool current = false,
}) =>
    PlayerSeasonStats(
      seasonName: name,
      isCurrent: current,
      matchesPlayed: played,
      wins: wins,
      draws: 0,
      losses: played - wins,
      goals: goals,
      hdm: hdm,
    );
