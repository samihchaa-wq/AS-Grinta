import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlayerStatistics {
  const PlayerStatistics({
    required this.profileId,
    required this.name,
    required this.matches,
    required this.goals,
    required this.assists,
    required this.motm,
  });

  final String profileId;
  final String name;
  final int matches;
  final int goals;
  final int assists;
  final int motm;
}

class StatisticsRepository {
  StatisticsRepository(this._client);

  final SupabaseClient _client;

  Future<List<PlayerStatistics>> fetchCareerStatistics() async {
    final profilesResponse = await _client
        .from('profiles')
        .select('id, first_name, last_name, status')
        .order('first_name')
        .order('last_name');
    final participantsResponse =
        await _client.from('match_participants').select('match_id, profile_id');
    final goalsResponse = await _client
        .from('goals')
        .select('team, scorer_profile_id, assist_profile_id');
    final motmResponse = await _client.from('match_motm').select('profile_id');

    final matchesByPlayer = <String, Set<String>>{};
    for (final row in participantsResponse as List) {
      final map = Map<String, dynamic>.from(row);
      final profileId = map['profile_id']?.toString();
      final matchId = map['match_id']?.toString();
      if (profileId == null || matchId == null) continue;
      matchesByPlayer.putIfAbsent(profileId, () => <String>{}).add(matchId);
    }

    final goalsByPlayer = <String, int>{};
    final assistsByPlayer = <String, int>{};
    for (final row in goalsResponse as List) {
      final map = Map<String, dynamic>.from(row);
      if (map['team'] != 'as_grinta') continue;
      final scorerId = map['scorer_profile_id']?.toString();
      final assistId = map['assist_profile_id']?.toString();
      if (scorerId != null) {
        goalsByPlayer[scorerId] = (goalsByPlayer[scorerId] ?? 0) + 1;
      }
      if (assistId != null) {
        assistsByPlayer[assistId] = (assistsByPlayer[assistId] ?? 0) + 1;
      }
    }

    final motmByPlayer = <String, int>{};
    for (final row in motmResponse as List) {
      final map = Map<String, dynamic>.from(row);
      final profileId = map['profile_id']?.toString();
      if (profileId != null) {
        motmByPlayer[profileId] = (motmByPlayer[profileId] ?? 0) + 1;
      }
    }

    final result = <PlayerStatistics>[];
    for (final row in profilesResponse as List) {
      final map = Map<String, dynamic>.from(row);
      if (map['status'] != 'active') continue;
      final id = map['id'].toString();
      final firstName = (map['first_name'] ?? '').toString().trim();
      final lastName = (map['last_name'] ?? '').toString().trim();
      final name = '$firstName $lastName'.trim();
      result.add(
        PlayerStatistics(
          profileId: id,
          name: name.isEmpty ? 'Joueur sans nom' : name,
          matches: matchesByPlayer[id]?.length ?? 0,
          goals: goalsByPlayer[id] ?? 0,
          assists: assistsByPlayer[id] ?? 0,
          motm: motmByPlayer[id] ?? 0,
        ),
      );
    }

    result.sort((a, b) {
      final goals = b.goals.compareTo(a.goals);
      if (goals != 0) return goals;
      final assists = b.assists.compareTo(a.assists);
      if (assists != 0) return assists;
      return a.name.compareTo(b.name);
    });
    return result;
  }
}

final statisticsRepositoryProvider = Provider<StatisticsRepository>((ref) {
  return StatisticsRepository(ref.watch(supabaseClientProvider));
});

final careerStatisticsProvider = FutureProvider<List<PlayerStatistics>>((ref) {
  return ref.watch(statisticsRepositoryProvider).fetchCareerStatistics();
});
