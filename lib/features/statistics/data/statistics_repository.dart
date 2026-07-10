import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlayerStatistics {
  const PlayerStatistics({
    required this.profileId,
    required this.firstName,
    required this.lastName,
    this.surnom,
    required this.isGoalkeeper,
    required this.matches,
    required this.goals,
    required this.assists,
    required this.penaltyFaults,
    required this.motm,
    required this.cleanSheets,
  });

  final String profileId;
  final String firstName;
  final String lastName;
  final String? surnom;
  final bool isGoalkeeper;
  final int matches;
  final int goals;
  final int assists;
  final int penaltyFaults;
  final int motm;
  final int cleanSheets;

  String get fullName => '$firstName $lastName'.trim();
  String get displayName {
    final nickname = surnom?.trim() ?? '';
    if (nickname.isNotEmpty) return nickname;
    if (firstName.trim().isNotEmpty) return firstName.trim();
    return fullName.isEmpty ? 'Joueur sans nom' : fullName;
  }

  String get sortName => displayName.toLowerCase();
}

class StatisticsRepository {
  StatisticsRepository(this._client);

  final SupabaseClient _client;

  Future<List<PlayerStatistics>> fetchCareerStatistics() async {
    final profilesResponse = await _client
        .from('profiles')
        .select('id,first_name,last_name,surnom,is_goalkeeper,status,role')
        .eq('status', 'active')
        .eq('role', 'pronostiqueur');
    final statsResponse = await _client.from('v_player_career_stats').select('''
          profile_id,
          matches_played,
          goals,
          assists,
          penalty_faults,
          motm,
          clean_sheets
        ''');

    final statsByProfile = <String, Map<String, dynamic>>{};
    for (final row in statsResponse as List) {
      final map = Map<String, dynamic>.from(row);
      statsByProfile[map['profile_id'].toString()] = map;
    }

    final result = <PlayerStatistics>[];
    for (final row in profilesResponse as List) {
      final profile = Map<String, dynamic>.from(row);
      final id = profile['id'].toString();
      final stats = statsByProfile[id] ?? const <String, dynamic>{};
      result.add(
        PlayerStatistics(
          profileId: id,
          firstName: (profile['first_name'] ?? '').toString().trim(),
          lastName: (profile['last_name'] ?? '').toString().trim(),
          surnom: profile['surnom']?.toString(),
          isGoalkeeper: profile['is_goalkeeper'] == true,
          matches: int.tryParse('${stats['matches_played'] ?? 0}') ?? 0,
          goals: int.tryParse('${stats['goals'] ?? 0}') ?? 0,
          assists: int.tryParse('${stats['assists'] ?? 0}') ?? 0,
          penaltyFaults:
              int.tryParse('${stats['penalty_faults'] ?? 0}') ?? 0,
          motm: int.tryParse('${stats['motm'] ?? 0}') ?? 0,
          cleanSheets: int.tryParse('${stats['clean_sheets'] ?? 0}') ?? 0,
        ),
      );
    }

    return result;
  }
}

final statisticsRepositoryProvider = Provider<StatisticsRepository>((ref) {
  return StatisticsRepository(ref.watch(supabaseClientProvider));
});

final careerStatisticsProvider = FutureProvider<List<PlayerStatistics>>((ref) {
  return ref.watch(statisticsRepositoryProvider).fetchCareerStatistics();
});
