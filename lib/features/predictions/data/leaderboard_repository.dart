import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.profileId,
    required this.name,
    required this.matchPoints,
    required this.seasonPoints,
    required this.totalPoints,
    required this.matchBons,
    required this.matchExacts,
    required this.seasonBons,
    required this.seasonExacts,
  });

  final String profileId;
  final String name;

  /// Points bruts sur chaque compétition (pour l'affichage détaillé).
  final double matchPoints;
  final double seasonPoints;

  /// Score final pondéré 70 % matchs / 30 % saison, normalisé (0 à 100).
  final double totalPoints;

  /// Statistiques matchs : bons vainqueurs et scores exacts trouvés.
  final int matchBons;
  final int matchExacts;

  /// Statistiques saison : joueurs où l'on est le plus proche (égalités
  /// comprises) et où l'on a trouvé le bon nombre de buts.
  final int seasonBons;
  final int seasonExacts;
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
          match_points,
          season_points,
          total_points,
          match_bons,
          match_exacts,
          season_bons,
          season_exacts
        ''')
        .order('total_points', ascending: false)
        .order('match_points', ascending: false)
        .order('first_name');

    return (response as List).map((row) {
      final map = Map<String, dynamic>.from(row);
      final firstName = (map['first_name'] ?? '').toString().trim();
      final displayName = firstName.isNotEmpty ? firstName : 'Compte sans nom';

      return LeaderboardEntry(
        profileId: map['profile_id'].toString(),
        name: displayName,
        matchPoints: (map['match_points'] as num?)?.toDouble() ?? 0,
        seasonPoints: (map['season_points'] as num?)?.toDouble() ?? 0,
        totalPoints: (map['total_points'] as num?)?.toDouble() ?? 0,
        matchBons: (map['match_bons'] as num?)?.toInt() ?? 0,
        matchExacts: (map['match_exacts'] as num?)?.toInt() ?? 0,
        seasonBons: (map['season_bons'] as num?)?.toInt() ?? 0,
        seasonExacts: (map['season_exacts'] as num?)?.toInt() ?? 0,
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
