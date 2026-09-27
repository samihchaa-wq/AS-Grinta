import 'dart:async';

import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/badges/data/statistics_badge_emblems_provider.dart';
import 'package:as_grinta/features/statistics/data/statistics_repository.dart';
import 'package:as_grinta/features/statistics/presentation/stats_hub_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Écran Statistiques, avec un faux dépôt de données : ce que voit un joueur
/// selon les chiffres reçus, le tri des colonnes et le choix de la période.
void main() {
  late _FakeStatisticsRepository repository;

  setUp(() => repository = _FakeStatisticsRepository());

  Future<void> pumpStats(WidgetTester tester, {String? section}) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
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
}

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
    scoreMarginDistribution: const {},
    bestWinStreak: noStreak,
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
