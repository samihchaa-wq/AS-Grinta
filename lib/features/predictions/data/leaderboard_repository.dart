import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.profileId,
    required this.name,
    required this.matchPoints,
    required this.seasonPoints,
    required this.matchMaxPoints,
    required this.seasonMaxPoints,
    required this.matchPercentage,
    required this.seasonPercentage,
  });

  final String profileId;
  final String name;
  final double matchPoints;
  final double seasonPoints;
  final double matchMaxPoints;
  final double seasonMaxPoints;
  final double matchPercentage;
  final double seasonPercentage;

  double get totalPoints => matchPoints + seasonPoints;
  double get totalMaxPoints => matchMaxPoints + seasonMaxPoints;
  double get totalPercentage =>
      totalMaxPoints <= 0 ? 0 : totalPoints * 100 / totalMaxPoints;
}

class LeaderboardRepository {
  LeaderboardRepository(this._client);

  final SupabaseClient _client;

  Future<List<LeaderboardEntry>> fetchCurrentLeaderboard() async {
    final response = await _client
        .from('v_classement_general')
        .select('''
          profile_id,
          first_name,
          last_name,
          surnom,
          match_points,
          season_points,
          total_points,
          match_max_points,
          season_max_points,
          match_percentage,
          season_percentage
        ''')
        .order('total_points', ascending: false)
        .order('match_points', ascending: false)
        .order('first_name');

    return (response as List).map((row) {
      final map = Map<String, dynamic>.from(row);
      final firstName = (map['first_name'] ?? '').toString().trim();
      final nickname = (map['surnom'] ?? '').toString().trim();
      final displayName = nickname.isNotEmpty
          ? nickname
          : (firstName.isNotEmpty ? firstName : 'Compte sans nom');

      return LeaderboardEntry(
        profileId: map['profile_id'].toString(),
        name: displayName,
        matchPoints: (map['match_points'] as num?)?.toDouble() ?? 0,
        seasonPoints: (map['season_points'] as num?)?.toDouble() ?? 0,
        matchMaxPoints: (map['match_max_points'] as num?)?.toDouble() ?? 0,
        seasonMaxPoints: (map['season_max_points'] as num?)?.toDouble() ?? 0,
        matchPercentage: (map['match_percentage'] as num?)?.toDouble() ?? 0,
        seasonPercentage: (map['season_percentage'] as num?)?.toDouble() ?? 0,
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
