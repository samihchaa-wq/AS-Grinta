import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlayerStatistics {
  const PlayerStatistics({
    required this.id,
    required this.firstName,
    required this.isGoalkeeper,
    required this.goals,
    required this.cleanSheets,
  });

  final String id;
  final String firstName;
  final bool isGoalkeeper;
  final int goals;
  final int cleanSheets;

  String get displayName {
    final first = firstName.trim();
    return first.isEmpty ? 'Joueur sans nom' : first;
  }

  String get sortName => displayName.toLowerCase();
}

class StatisticsRepository {
  StatisticsRepository(this._client);

  final SupabaseClient _client;

  /// Classement de la saison ouverte : buts par joueur + clean sheets du
  /// gardien. Si aucune saison n'est ouverte, on prend la plus récente.
  Future<List<PlayerStatistics>> fetchCareerStatistics() async {
    final openSeason = await _client
        .from('seasons')
        .select('id')
        .eq('status', 'open')
        .maybeSingle();
    String? seasonId = openSeason?['id']?.toString();
    if (seasonId == null) {
      final latest = await _client
          .from('seasons')
          .select('id')
          .order('name', ascending: false)
          .limit(1)
          .maybeSingle();
      seasonId = latest?['id']?.toString();
    }
    if (seasonId == null) return const [];

    final rows = await _client
        .from('v_scorer_standings')
        .select('season_player_id,first_name,is_goalkeeper,goals,clean_sheets')
        .eq('season_id', seasonId);

    return (rows as List).map((row) {
      final map = Map<String, dynamic>.from(row);
      return PlayerStatistics(
        id: map['season_player_id'].toString(),
        firstName: (map['first_name'] ?? '').toString().trim(),
        isGoalkeeper: map['is_goalkeeper'] == true,
        goals: int.tryParse('${map['goals'] ?? 0}') ?? 0,
        cleanSheets: int.tryParse('${map['clean_sheets'] ?? 0}') ?? 0,
      );
    }).toList();
  }
}

final statisticsRepositoryProvider = Provider<StatisticsRepository>((ref) {
  return StatisticsRepository(ref.watch(supabaseClientProvider));
});

final careerStatisticsProvider = FutureProvider<List<PlayerStatistics>>((ref) {
  return ref.watch(statisticsRepositoryProvider).fetchCareerStatistics();
});
