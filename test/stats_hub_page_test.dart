import 'dart:async';

import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/badges/data/statistics_badge_emblems_provider.dart';
import 'package:as_grinta/features/predictions/data/leaderboard_repository.dart';
import 'package:as_grinta/features/statistics/data/statistics_repository.dart';
import 'package:as_grinta/features/statistics/presentation/stats_hub_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Écran Statistiques, avec un faux dépôt de données : ce que voit un joueur
/// selon les chiffres reçus, le tri des colonnes et le choix de la période.
void main() {
  late _FakeStatisticsRepository repository;
  var leaderboard = <LeaderboardEntry>[];

  setUp(() {
    repository = _FakeStatisticsRepository();
    leaderboard = <LeaderboardEntry>[];
  });

  Future<void> pumpStats(
    WidgetTester tester, {
    String? section,
    Size size = const Size(900, 1200),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => AuthController(_FakeAuthRepository()),
          ),
          statisticsRepositoryProvider.overrideWithValue(repository),
          statisticsBadgeEmblemsProvider.overrideWith(
            (ref) async => const <String, List<StatisticsBadgeEmblemData>>{},
          ),
          leaderboardProvider.overrideWith((ref) async => leaderboard),
        ],
        child: MaterialApp(home: StatsHubPage(initialSection: section)),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> playerOrder(WidgetTester tester) {
    final names = {'Karim', 'Maxime', 'Julien'};
    final found = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>()
        .where(names.contains)
        .toList();
    return found;
  }

  testWidgets('affiche les joueurs de la saison actuelle avec leurs chiffres',
      (tester) async {
    repository.players[StatisticsPeriod.current] = [
      _player('Karim', played: 12, goals: 7, assists: 3),
      _player('Maxime', played: 10, goals: 2, assists: 1),
    ];

    await pumpStats(tester);

    expect(repository.requestedPlayers, [StatisticsPeriod.current]);
    expect(find.text('Karim'), findsOneWidget);
    expect(find.text('Maxime'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    // La saison en cours montre toujours la colonne des passes décisives.
    expect(find.text('PD'), findsOneWidget);
  });

  testWidgets('trier par buts range les joueurs du meilleur au moins bon',
      (tester) async {
    repository.players[StatisticsPeriod.current] = [
      _player('Karim', played: 12, goals: 1),
      _player('Maxime', played: 10, goals: 9),
      _player('Julien', played: 8, goals: 4),
    ];

    await pumpStats(tester);
    expect(playerOrder(tester), ['Karim', 'Maxime', 'Julien']);

    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    expect(playerOrder(tester), ['Maxime', 'Julien', 'Karim']);

    // Un second appui inverse l'ordre.
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    expect(playerOrder(tester), ['Karim', 'Julien', 'Maxime']);
  });

  testWidgets('une saison sans match validé l’annonce clairement',
      (tester) async {
    repository.players[StatisticsPeriod.current] = const [];

    await pumpStats(tester);

    expect(find.text('Pas encore de statistiques'), findsOneWidget);
    expect(
      find.text('Les stats apparaîtront après le premier match validé.'),
      findsOneWidget,
    );
  });

  testWidgets('une erreur de chargement affiche un message compréhensible',
      (tester) async {
    repository.playersError = StateError('Serveur indisponible');

    await pumpStats(tester);

    expect(find.text('Statistiques indisponibles'), findsOneWidget);
  });

  testWidgets('changer de période charge cette période', (tester) async {
    repository.players[StatisticsPeriod.current] = [
      _player('Karim', played: 12, goals: 7),
    ];
    repository.players[StatisticsPeriod.previous] = [
      _player('Maxime', played: 20, goals: 11),
    ];

    await pumpStats(tester);
    await tester.tap(find.text('Précédente'));
    await tester.pumpAndSettle();

    expect(
      repository.requestedPlayers,
      [StatisticsPeriod.current, StatisticsPeriod.previous],
    );
    expect(find.text('Maxime'), findsOneWidget);
    expect(find.text('Karim'), findsNothing);
    // Aucune passe enregistrée sur cette période : pas de colonne vide.
    expect(find.text('PD'), findsNothing);
  });

  testWidgets('l’onglet Équipe affiche le bilan de l’équipe', (tester) async {
    repository.team[StatisticsPeriod.current] = _team(
      played: 10,
      wins: 6,
      draws: 1,
      losses: 3,
      goalsFor: 23,
      goalsAgainst: 14,
    );

    await pumpStats(tester, section: 'team');

    expect(repository.requestedTeams, [StatisticsPeriod.current]);
    expect(find.text('23'), findsWidgets);
    expect(find.text('14'), findsWidgets);
  });

  testWidgets(
      'le bilan tient en un seul anneau et les séries en chiffres clés, '
      'sans barre rapportée au nombre de matchs', (tester) async {
    repository.team[StatisticsPeriod.current] = _team(
      played: 315,
      wins: 213,
      draws: 46,
      losses: 56,
      goalsFor: 1246,
      goalsAgainst: 589,
      bestWinStreak: const TeamStreak(
        length: 12,
        startDate: '2019-11-07',
        endDate: '2020-10-05',
      ),
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await pumpStats(tester, section: 'team');
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('315'), findsOneWidget);
    // 67,6 % + 14,6 % + 17,8 % : arrondis à 68 + 14 + 18 = 100.
    expect(find.text('68 %'), findsOneWidget);
    expect(find.text('14 %'), findsOneWidget);
    expect(find.text('18 %'), findsOneWidget);
    expect(find.text('+657'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('victoires d’affilée'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('du 07/11/2019'), findsOneWidget);
    expect(find.textContaining('/ 315'), findsNothing);
  });

  testWidgets(
      'l’écart de score s’affiche en graphique sur un téléphone, '
      'avec des axes adaptés aux résultats', (tester) async {
    repository.team[StatisticsPeriod.current] = _team(
      played: 5,
      wins: 4,
      draws: 1,
      losses: 0,
      goalsFor: 15,
      goalsAgainst: 4,
      scoreMarginDistribution: const {0: 1, 1: 1, 3: 3},
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await pumpStats(tester, section: 'team');
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Séries'),
      300,
      scrollable: find.byType(Scrollable).last,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Écart de buts'), findsOneWidget);
    final chart = find.ancestor(
      of: find.text('Écart de buts'),
      matching: find.byType(Card),
    );
    Finder inChart(String text) =>
        find.descendant(of: chart, matching: find.text(text));
    // Abscisse : du nul (0) au plus large écart observé (3). Ordonnée : de 0
    // au plus grand nombre de matchs pour un même écart (3). Rien au-delà.
    for (final label in ['0', '1', '2', '3']) {
      expect(inChart(label), findsWidgets);
    }
    expect(inChart('4'), findsNothing);
    expect(find.text('Victoires'), findsOneWidget);
    expect(find.text('Séries'), findsOneWidget);
  });
  testWidgets(
      'un très large écart garde une colonne par écart, sans regroupement',
      (tester) async {
    repository.team[StatisticsPeriod.current] = _team(
      played: 3,
      wins: 2,
      draws: 0,
      losses: 1,
      goalsFor: 20,
      goalsAgainst: 6,
      scoreMarginDistribution: const {-4: 1, 2: 1, 14: 1},
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await pumpStats(tester, section: 'team');
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Écart de buts'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    final chart = find.ancestor(
      of: find.text('Écart de buts'),
      matching: find.byType(Card),
    );

    expect(tester.takeException(), isNull);
    Finder inChart(String text) =>
        find.descendant(of: chart, matching: find.text(text));
    expect(inChart('14'), findsOneWidget);
    expect(inChart('13'), findsOneWidget);
    expect(
      find.descendant(of: chart, matching: find.textContaining('+')),
      findsNothing,
    );
    // 19 colonnes (de -4 à +14) : trop pour l’écran, le graphique défile.
    expect(
      find.descendant(
        of: chart,
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
  });

  testWidgets('le classement Prono compte les pronos avant les bons',
      (tester) async {
    leaderboard = [
      _predictor('Karim', pronos: 14, bons: 9, exacts: 3, points: .37),
      _predictor('Maxime', pronos: 11, bons: 5, exacts: 1, points: .18),
    ];

    await pumpStats(tester, section: 'rankings');

    // « Prono » est à la fois l'onglet et la nouvelle colonne.
    final pronoHeader = find.text('Prono').last;
    final bonsHeader = find.text('Bons');
    expect(bonsHeader, findsOneWidget);
    expect(
      tester.getCenter(pronoHeader).dx,
      lessThan(tester.getCenter(bonsHeader).dx),
    );
    expect(find.text('14'), findsOneWidget);
    expect(find.text('11'), findsOneWidget);
  });

  testWidgets('la colonne Prono tient sur un écran de téléphone',
      (tester) async {
    leaderboard = [
      _predictor('Karim', pronos: 104, bons: 61, exacts: 12, points: 2.47),
    ];

    await pumpStats(tester, section: 'rankings', size: const Size(360, 780));

    expect(tester.takeException(), isNull);
    expect(find.text('104'), findsOneWidget);
    expect(find.text('247'), findsOneWidget);
  });

  testWidgets('les points du classement Prono sont centrés', (tester) async {
    leaderboard = [
      _predictor('Karim', pronos: 14, bons: 9, exacts: 3, points: .37),
    ];

    await pumpStats(tester, section: 'rankings');

    expect(tester.widget<Text>(find.text('37')).textAlign, TextAlign.center);
  });

  testWidgets('sans total publié par la base, la colonne Prono reste vide',
      (tester) async {
    leaderboard = [
      _predictor('Karim', pronos: null, bons: 9, exacts: 3, points: .37),
    ];

    await pumpStats(tester, section: 'rankings');

    expect(find.text('Karim'), findsOneWidget);
    expect(find.text('–'), findsOneWidget);
  });
}

LeaderboardEntry _predictor(
  String name, {
  required int? pronos,
  required int bons,
  required int exacts,
  required double points,
}) =>
    LeaderboardEntry(
      profileId: 'profil-$name',
      name: name,
      matchPoints: points,
      matchBons: bons,
      matchExacts: exacts,
      matchPronos: pronos,
    );

PlayerStatistics _player(
  String name, {
  required int played,
  int goals = 0,
  int assists = 0,
}) =>
    PlayerStatistics(
      period: StatisticsPeriod.current,
      periodLabel: 'Saison actuelle',
      rank: 1,
      displayOrder: 1,
      playerName: name,
      profileId: null,
      isGoalkeeper: false,
      matchesPlayed: played,
      wins: 0,
      draws: 0,
      losses: 0,
      goals: goals,
      assists: assists,
      hdm: 0,
      cleanSheets: 0,
    );

TeamStatistics _team({
  required int played,
  required int wins,
  required int draws,
  required int losses,
  required int goalsFor,
  required int goalsAgainst,
  Map<int, int> scoreMarginDistribution = const {},
  TeamStreak? bestWinStreak,
}) {
  const noStreak = TeamStreak(length: 0, startDate: null, endDate: null);
  return TeamStatistics(
    period: StatisticsPeriod.current,
    periodLabel: 'Saison actuelle',
    matchesPlayed: played,
    wins: wins,
    draws: draws,
    losses: losses,
    goalsFor: goalsFor,
    goalsAgainst: goalsAgainst,
    goalDifference: goalsFor - goalsAgainst,
    recentResults: const ['V', 'N', 'D'],
    scoreMarginDistribution: scoreMarginDistribution,
    bestWinStreak: bestWinStreak ?? noStreak,
    bestUnbeatenStreak: noStreak,
    worstLossStreak: noStreak,
    worstWinlessStreak: noStreak,
  );
}

class _FakeStatisticsRepository implements StatisticsRepository {
  final players = <StatisticsPeriod, List<PlayerStatistics>>{};
  final team = <StatisticsPeriod, TeamStatistics>{};
  final requestedPlayers = <StatisticsPeriod>[];
  final requestedTeams = <StatisticsPeriod>[];
  Object? playersError;

  @override
  Future<StatisticsPeriodData> fetchPlayers(StatisticsPeriod period) async {
    requestedPlayers.add(period);
    final error = playersError;
    if (error != null) throw error;
    return StatisticsPeriodData(
      period: period,
      label: period.fallbackLabel,
      players: players[period] ?? const [],
    );
  }

  @override
  Future<TeamStatistics> fetchTeam(StatisticsPeriod period) async {
    requestedTeams.add(period);
    return team[period] ??
        _team(
          played: 0,
          wins: 0,
          draws: 0,
          losses: 0,
          goalsFor: 0,
          goalsAgainst: 0,
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthRepository implements AuthRepository {
  final _events = StreamController<Never>.broadcast();

  @override
  Stream<Never> get authStateChanges => _events.stream;

  @override
  bool get hasSession => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
