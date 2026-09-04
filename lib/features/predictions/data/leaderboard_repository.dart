import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/utils/name_validation.dart';
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

  /// Score final : addition directe des points matchs et saison.
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

    final rows = (response as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);

    // Les statistiques nomment tout le monde par son vrai prénom, et n'ajoutent
    // l'initiale du nom que pour départager deux homonymes. Le surnom reste
    // réservé au Calendrier.
    final lastInitials = await _lastInitialsByProfile(
      rows.map((row) => row['profile_id'].toString()).toSet(),
    );
    final firstNameCounts = <String, int>{};
    for (final row in rows) {
      final key = (row['first_name'] ?? '').toString().trim().toLowerCase();
      if (key.isEmpty) continue;
      firstNameCounts[key] = (firstNameCounts[key] ?? 0) + 1;
    }

    return rows.map((map) {
      final profileId = map['profile_id'].toString();
      final firstName = (map['first_name'] ?? '').toString().trim();
      final lastInitial = lastInitials[profileId];
      final isHomonym = (firstNameCounts[firstName.toLowerCase()] ?? 0) > 1;
      final displayName = firstName.isEmpty
          ? 'Compte sans nom'
          : statisticsName(
              firstName,
              lastInitial: lastInitial,
              isHomonym: isHomonym,
            );

      return LeaderboardEntry(
        profileId: profileId,
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

  /// Initiale du nom de famille des membres qui sont aussi joueurs, lue sur
  /// l'effectif : le profil ne publie pas le nom de famille. Un pronostiqueur
  /// qui n'a jamais été inscrit à l'effectif n'en a pas, il reste alors
  /// affiché sous son seul prénom.
  Future<Map<String, String>> _lastInitialsByProfile(
    Set<String> profileIds,
  ) async {
    if (profileIds.isEmpty) return const {};
    final response = await _client
        .from('season_players')
        .select('profile_id,last_name')
        .inFilter('profile_id', profileIds.toList(growable: false));

    final initials = <String, String>{};
    for (final row in response as List) {
      final map = Map<String, dynamic>.from(row as Map);
      final profileId = map['profile_id']?.toString();
      final lastName = (map['last_name'] ?? '').toString().trim();
      if (profileId == null || profileId.isEmpty || lastName.isEmpty) continue;
      initials.putIfAbsent(profileId, () => lastName[0].toUpperCase());
    }
    return initials;
  }
}

final leaderboardRepositoryProvider = Provider<LeaderboardRepository>((ref) {
  return LeaderboardRepository(ref.watch(supabaseClientProvider));
});

final leaderboardProvider = FutureProvider<List<LeaderboardEntry>>((ref) {
  return ref.watch(leaderboardRepositoryProvider).fetchCurrentLeaderboard();
});
