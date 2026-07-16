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

class StatisticsRepository {
  StatisticsRepository(this._client);

  final SupabaseClient _client;

  Future<StatisticsPeriodData> fetch(StatisticsPeriod period) async {
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
          clean_sheets
        ''').eq('period_key', period.databaseKey);

    // Association prénom → compte, pour afficher les badges des joueurs qui
    // ont un compte (les autres joueurs d'effectif n'en ont pas).
    final rosterRows = await _client
        .from('season_players')
        .select('first_name, profile_id')
        .not('profile_id', 'is', null);
    final profileByFirstName = <String, String>{};
    for (final row in rosterRows as List) {
      final m = Map<String, dynamic>.from(row as Map);
      final first = (m['first_name'] ?? '').toString().trim().toLowerCase();
      final pid = m['profile_id']?.toString();
      if (first.isNotEmpty && pid != null) {
        profileByFirstName.putIfAbsent(first, () => pid);
      }
    }

    final players = (response as List).map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      final name = _firstName((map['player_name'] ?? 'Joueur').toString());
      return PlayerStatistics(
        period: period,
        periodLabel: (map['period_label'] ?? period.fallbackLabel).toString(),
        rank: (map['display_rank'] as num?)?.toInt() ?? 0,
        displayOrder: (map['display_order'] as num?)?.toInt() ?? 9999,
        playerName: name,
        profileId: profileByFirstName[name.toLowerCase()],
        isGoalkeeper: map['is_goalkeeper'] == true,
        matchesPlayed: (map['matches_played'] as num?)?.toInt(),
        wins: (map['wins'] as num?)?.toInt(),
        draws: (map['draws'] as num?)?.toInt(),
        losses: (map['losses'] as num?)?.toInt(),
        goals: (map['goals'] as num?)?.toInt() ?? 0,
        hdm: (map['hdm'] as num?)?.toInt(),
        cleanSheets: (map['clean_sheets'] as num?)?.toInt() ?? 0,
      );
    }).toList()
      ..sort((a, b) {
        final byGoalkeeper = (a.isGoalkeeper ? 1 : 0).compareTo(
          b.isGoalkeeper ? 1 : 0,
        );
        if (byGoalkeeper != 0) return byGoalkeeper;
        final byRank = a.rank.compareTo(b.rank);
        if (byRank != 0) return byRank;
        final byOrder = a.displayOrder.compareTo(b.displayOrder);
        if (byOrder != 0) return byOrder;
        return a.playerName.toLowerCase().compareTo(
              b.playerName.toLowerCase(),
            );
      });

    return StatisticsPeriodData(
      period: period,
      label: players.isEmpty ? period.fallbackLabel : players.first.periodLabel,
      players: players,
    );
  }
}

final statisticsRepositoryProvider = Provider<StatisticsRepository>((ref) {
  return StatisticsRepository(ref.watch(supabaseClientProvider));
});

final statisticsPeriodProvider = FutureProvider.autoDispose
    .family<StatisticsPeriodData, StatisticsPeriod>((ref, period) {
  return ref.watch(statisticsRepositoryProvider).fetch(period);
});
