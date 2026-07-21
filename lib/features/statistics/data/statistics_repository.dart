import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum StatisticsPeriod { current, previous, allTime }

String _firstName(String fullName) {
  final normalizedName = fullName.trim();
  if (normalizedName.isEmpty) return fullName;
  return normalizedName.split(RegExp(r'\s+')).first;
}

extension StatisticsPeriodKey on StatisticsPeriod {
  String get databaseKey => switch (this) {
        StatisticsPeriod.current => 'current',
        StatisticsPeriod.previous => 'previous',
        StatisticsPeriod.allTime => 'all_time',
      };

  String get fallbackLabel => switch (this) {
        StatisticsPeriod.current => 'Saison actuelle',
        StatisticsPeriod.previous => 'Saison précédente',
        StatisticsPeriod.allTime => 'Toutes saisons',
      };
}

class PlayerStatistics {
  const PlayerStatistics({
    required this.period,
    required this.periodLabel,
    required this.rank,
    required this.displayOrder,
    required this.playerName,
    required this.profileId,
    required this.isGoalkeeper,
    required this.matchesPlayed,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goals,
    required this.hdm,
    required this.cleanSheets,
  });

  final StatisticsPeriod period;
  final String periodLabel;
  final int rank;
  final int displayOrder;
  final String playerName;

  /// L'identifiant du compte lié à ce joueur (pour afficher ses badges).
  /// `null` si le joueur d'effectif n'a pas de compte.
  final String? profileId;
  final bool isGoalkeeper;
  final int? matchesPlayed;
  final int? wins;
  final int? draws;
  final int? losses;
  final int goals;
  final int? hdm;
  final int cleanSheets;

  bool get hasHistoricalBreakdown => matchesPlayed != null;
}

class StatisticsPeriodData {
  const StatisticsPeriodData({
    required this.period,
    required this.label,
    required this.players,
  });

  final StatisticsPeriod period;
  final String label;
  final List<PlayerStatistics> players;
}

class TeamStatistics {
  const TeamStatistics({
    required this.period,
    required this.periodLabel,
    required this.matchesPlayed,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.goalDifference,
    required this.cleanSheets,
  });

  final StatisticsPeriod period;
  final String periodLabel;
  final int matchesPlayed;
  final int wins;
  final int draws;
  final int losses;
  final int goalsFor;
  final int goalsAgainst;
  final int goalDifference;
  final int cleanSheets;

  double get winRate => matchesPlayed == 0 ? 0 : wins * 100 / matchesPlayed;
  double get goalsForPerMatch =>
      matchesPlayed == 0 ? 0 : goalsFor / matchesPlayed;
  double get goalsAgainstPerMatch =>
      matchesPlayed == 0 ? 0 : goalsAgainst / matchesPlayed;
}

class StatisticsRepository {
  StatisticsRepository(this._client);

  final SupabaseClient _client;

  Future<StatisticsPeriodData> fetchPlayers(StatisticsPeriod period) async {
    final response = await _client.from('v_statistics_players').select('''
          period_key,
          period_label,
          display_rank,
          display_order,
          player_name,
          is_goalkeeper,
          matches_played,
          wins,
          draws,
          losses,
          goals,
          hdm,
          clean_sheets,
          profile_id
        ''').eq('period_key', period.databaseKey);

    // Un seul classement, gardiens et joueurs de champ confondus, trié par
    // matchs joués (puis buts, puis nom). Le rang est recalculé ici (ex æquo
    // en matchs joués = même rang).
    final rows = (response as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList()
      ..sort((a, b) {
        final ma = (a['matches_played'] as num?)?.toInt() ?? 0;
        final mb = (b['matches_played'] as num?)?.toInt() ?? 0;
        if (mb != ma) return mb.compareTo(ma);
        final ga = (a['goals'] as num?)?.toInt() ?? 0;
        final gb = (b['goals'] as num?)?.toInt() ?? 0;
        if (gb != ga) return gb.compareTo(ga);
        return _firstName((a['player_name'] ?? '').toString())
            .toLowerCase()
            .compareTo(
              _firstName((b['player_name'] ?? '').toString()).toLowerCase(),
            );
      });

    final players = <PlayerStatistics>[];
    var rank = 0;
    int? prevMatches;
    for (var i = 0; i < rows.length; i++) {
      final map = rows[i];
      final matches = (map['matches_played'] as num?)?.toInt();
      if (prevMatches == null || (matches ?? 0) != prevMatches) {
        rank = i + 1;
        prevMatches = matches ?? 0;
      }
      final name = _firstName((map['player_name'] ?? 'Joueur').toString());
      players.add(
        PlayerStatistics(
          period: period,
          periodLabel:
              (map['period_label'] ?? period.fallbackLabel).toString(),
          rank: rank,
          displayOrder: (map['display_order'] as num?)?.toInt() ?? 9999,
          playerName: name,
          profileId: map['profile_id']?.toString(),
          isGoalkeeper: map['is_goalkeeper'] == true,
          matchesPlayed: matches,
          wins: (map['wins'] as num?)?.toInt(),
          draws: (map['draws'] as num?)?.toInt(),
          losses: (map['losses'] as num?)?.toInt(),
          goals: (map['goals'] as num?)?.toInt() ?? 0,
          hdm: (map['hdm'] as num?)?.toInt(),
          cleanSheets: (map['clean_sheets'] as num?)?.toInt() ?? 0,
        ),
      );
    }

    return StatisticsPeriodData(
      period: period,
      label: players.isEmpty ? period.fallbackLabel : players.first.periodLabel,
      players: players,
    );
  }

  Future<TeamStatistics> fetchTeam(StatisticsPeriod period) async {
    final response = await _client
        .from('v_statistics_team')
        .select('''
          period_key,
          period_label,
          matches_played,
          wins,
          draws,
          losses,
          goals_for,
          goals_against,
          goal_difference,
          clean_sheets
        ''')
        .eq('period_key', period.databaseKey)
        .maybeSingle();

    final map = response == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(response);

    return TeamStatistics(
      period: period,
      periodLabel: (map['period_label'] ?? period.fallbackLabel).toString(),
      matchesPlayed: (map['matches_played'] as num?)?.toInt() ?? 0,
      wins: (map['wins'] as num?)?.toInt() ?? 0,
      draws: (map['draws'] as num?)?.toInt() ?? 0,
      losses: (map['losses'] as num?)?.toInt() ?? 0,
      goalsFor: (map['goals_for'] as num?)?.toInt() ?? 0,
      goalsAgainst: (map['goals_against'] as num?)?.toInt() ?? 0,
      goalDifference: (map['goal_difference'] as num?)?.toInt() ?? 0,
      cleanSheets: (map['clean_sheets'] as num?)?.toInt() ?? 0,
    );
  }
}

final statisticsRepositoryProvider = Provider<StatisticsRepository>((ref) {
  return StatisticsRepository(ref.watch(supabaseClientProvider));
});

final statisticsPeriodProvider = FutureProvider.autoDispose
    .family<StatisticsPeriodData, StatisticsPeriod>((ref, period) {
  return ref.watch(statisticsRepositoryProvider).fetchPlayers(period);
});

final teamStatisticsPeriodProvider = FutureProvider.autoDispose
    .family<TeamStatistics, StatisticsPeriod>((ref, period) {
  return ref.watch(statisticsRepositoryProvider).fetchTeam(period);
});
