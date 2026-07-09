import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.profileId,
    required this.name,
    required this.matchPoints,
    required this.seasonPoints,
  });

  final String profileId;
  final String name;
  final double matchPoints;
  final double seasonPoints;

  double get totalPoints => matchPoints + seasonPoints;
}

class LeaderboardRepository {
  LeaderboardRepository(this._client);

  final SupabaseClient _client;

  Future<List<LeaderboardEntry>> fetchCurrentLeaderboard() async {
    final response = await _client
        .from('v_classement_general')
        .select(
          'profile_id, first_name, last_name, match_points, season_points, total_points',
        )
        .order('total_points', ascending: false)
        .order('match_points', ascending: false)
        .order('last_name')
        .order('first_name');

    return (response as List).map((row) {
      final map = Map<String, dynamic>.from(row);
      final firstName = (map['first_name'] ?? '').toString().trim();
      final lastName = (map['last_name'] ?? '').toString().trim();
      final name = '$firstName $lastName'.trim();

      return LeaderboardEntry(
        profileId: map['profile_id'].toString(),
        name: name.isEmpty ? 'Compte sans nom' : name,
        matchPoints: (map['match_points'] as num?)?.toDouble() ?? 0,
        seasonPoints: (map['season_points'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
  }
}

final leaderboardRepositoryProvider = Provider<LeaderboardRepository>((ref) {
  return LeaderboardRepository(ref.watch(supabaseClientProvider));
});

final leaderboardProvider = FutureProvider<List<LeaderboardEntry>>((ref) {
  return ref.watch(leaderboardRepositoryProvider).fetchCurrentLeaderboard();
});
