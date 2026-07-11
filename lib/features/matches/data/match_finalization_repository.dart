import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MatchSheetPlayer {
  const MatchSheetPlayer({
    required this.id,
    required this.name,
    required this.isGoalkeeper,
  });

  final String id;
  final String name;
  final bool isGoalkeeper;
}

class MatchSheetPlayerStats {
  const MatchSheetPlayerStats({
    required this.present,
    required this.goals,
    required this.assists,
    required this.penaltyFaults,
    required this.cleanSheet,
  });

  final bool present;
  final int goals;
  final int assists;
  final int penaltyFaults;
  final bool cleanSheet;
}

class MatchSheetGuestStats {
  const MatchSheetGuestStats({
    required this.name,
    required this.position,
    required this.present,
    required this.goals,
    required this.assists,
    required this.penaltyFaults,
  });

  final String name;
  final String position;
  final bool present;
  final int goals;
  final int assists;
  final int penaltyFaults;
}

class MatchFinalizationContext {
  const MatchFinalizationContext({
    required this.players,
    required this.isValidated,
    required this.opponentScore,
    required this.motmProfileId,
    required this.existingPlayerStats,
    required this.existingGuests,
  });

  final List<MatchSheetPlayer> players;

  /// Vrai quand le match est déjà validé : la feuille sert alors de
  /// correction et arrive pré-remplie avec les statistiques existantes.
  final bool isValidated;
  final int opponentScore;
  final String? motmProfileId;
  final Map<String, MatchSheetPlayerStats> existingPlayerStats;
  final List<MatchSheetGuestStats> existingGuests;
}

class MatchFinalizationRepository {
  MatchFinalizationRepository(this._client);

  final SupabaseClient _client;

  Future<MatchFinalizationContext> fetch(String matchId) async {
    final match = await _client
        .from('matches')
        .select('season_id,status,score_adverse')
        .eq('id', matchId)
        .single();
    final seasonId = match['season_id'].toString();
    final status = (match['status'] ?? 'a_venir').toString();
    final isValidated = status == 'termine' || status == 'archive';

    final membershipRows = await _client
        .from('season_players')
        .select('profile_id,is_goalkeeper_snapshot')
        .eq('season_id', seasonId);
    final memberships = <String, bool>{};
    for (final row in membershipRows as List) {
      final map = Map<String, dynamic>.from(row);
      memberships[map['profile_id'].toString()] =
          map['is_goalkeeper_snapshot'] == true;
    }

    final existingPlayerStats = <String, MatchSheetPlayerStats>{};
    final existingGuests = <MatchSheetGuestStats>[];
    String? motmProfileId;

    if (isValidated) {
      final statRows = await _client
          .from('match_player_stats')
          .select('profile_id,present,goals,assists,penalty_faults,clean_sheet')
          .eq('match_id', matchId);
      for (final row in statRows as List) {
        final map = Map<String, dynamic>.from(row);
        final profileId = map['profile_id'].toString();
        existingPlayerStats[profileId] = MatchSheetPlayerStats(
          present: map['present'] == true,
          goals: (map['goals'] as num?)?.toInt() ?? 0,
          assists: (map['assists'] as num?)?.toInt() ?? 0,
          penaltyFaults: (map['penalty_faults'] as num?)?.toInt() ?? 0,
          cleanSheet: map['clean_sheet'] == true,
        );
        // Un joueur avec une feuille existante doit rester corrigeable même
        // s'il a quitté l'effectif de la saison depuis.
        memberships.putIfAbsent(profileId, () => false);
      }

      final guestRows = await _client
          .from('match_guest_stats')
          .select('display_name,position,present,goals,assists,penalty_faults')
          .eq('match_id', matchId)
          .order('display_name');
      for (final row in guestRows as List) {
        final map = Map<String, dynamic>.from(row);
        existingGuests.add(
          MatchSheetGuestStats(
            name: (map['display_name'] ?? '').toString(),
            position: (map['position'] ?? 'Joueur').toString(),
            present: map['present'] != false,
            goals: (map['goals'] as num?)?.toInt() ?? 0,
            assists: (map['assists'] as num?)?.toInt() ?? 0,
            penaltyFaults: (map['penalty_faults'] as num?)?.toInt() ?? 0,
          ),
        );
      }

      final motm = await _client
          .from('match_motm')
          .select('profile_id')
          .eq('match_id', matchId)
          .maybeSingle();
      motmProfileId = motm?['profile_id']?.toString();
    }

    if (memberships.isEmpty) {
      return MatchFinalizationContext(
        players: const [],
        isValidated: isValidated,
        opponentScore: (match['score_adverse'] as num?)?.toInt() ?? 0,
        motmProfileId: motmProfileId,
        existingPlayerStats: existingPlayerStats,
        existingGuests: existingGuests,
      );
    }

    final profileRows = await _client
        .from('profiles')
        .select('id,first_name,surnom,status,is_goalkeeper')
        .inFilter('id', memberships.keys.toList())
        .order('first_name');

    final players = (profileRows as List)
        .map((row) => Map<String, dynamic>.from(row))
        .where(
          (map) =>
              map['status'] == 'active' ||
              existingPlayerStats.containsKey(map['id'].toString()),
        )
        .map((map) {
      final firstName = (map['first_name'] ?? '').toString().trim();
      final nickname = (map['surnom'] ?? '').toString().trim();
      final id = map['id'].toString();
      return MatchSheetPlayer(
        id: id,
        name: nickname.isNotEmpty
            ? nickname
            : (firstName.isNotEmpty ? firstName : 'Joueur sans nom'),
        isGoalkeeper: memberships[id] == true || map['is_goalkeeper'] == true,
      );
    }).toList();

    return MatchFinalizationContext(
      players: players,
      isValidated: isValidated,
      opponentScore: (match['score_adverse'] as num?)?.toInt() ?? 0,
      motmProfileId: motmProfileId,
      existingPlayerStats: existingPlayerStats,
      existingGuests: existingGuests,
    );
  }
}

final matchFinalizationRepositoryProvider =
    Provider<MatchFinalizationRepository>((ref) {
  return MatchFinalizationRepository(ref.watch(supabaseClientProvider));
});

final matchFinalizationContextProvider = FutureProvider.autoDispose
    .family<MatchFinalizationContext, String>((ref, matchId) {
  return ref.watch(matchFinalizationRepositoryProvider).fetch(matchId);
});
