import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PostMatchPlayer {
  const PostMatchPlayer({
    required this.id,
    required this.name,
    required this.isGoalkeeper,
    required this.present,
    required this.goals,
    required this.assists,
    required this.penaltyFaults,
    required this.cleanSheet,
  });

  final String id;
  final String name;
  final bool isGoalkeeper;
  final bool present;
  final int goals;
  final int assists;
  final int penaltyFaults;
  final bool cleanSheet;

  PostMatchPlayer copyWith({
    bool? present,
    int? goals,
    int? assists,
    int? penaltyFaults,
    bool? cleanSheet,
  }) => PostMatchPlayer(
        id: id,
        name: name,
        isGoalkeeper: isGoalkeeper,
        present: present ?? this.present,
        goals: goals ?? this.goals,
        assists: assists ?? this.assists,
        penaltyFaults: penaltyFaults ?? this.penaltyFaults,
        cleanSheet: cleanSheet ?? this.cleanSheet,
      );

  Map<String, dynamic> toJson() => {
        'profile_id': id,
        'present': present,
        'goals': goals,
        'assists': assists,
        'penalty_faults': penaltyFaults,
        'clean_sheet': cleanSheet,
      };
}

class PostMatchGuest {
  const PostMatchGuest({
    required this.name,
    this.goals = 0,
    this.assists = 0,
    this.penaltyFaults = 0,
  });

  final String name;
  final int goals;
  final int assists;
  final int penaltyFaults;

  PostMatchGuest copyWith({int? goals, int? assists, int? penaltyFaults}) =>
      PostMatchGuest(
        name: name,
        goals: goals ?? this.goals,
        assists: assists ?? this.assists,
        penaltyFaults: penaltyFaults ?? this.penaltyFaults,
      );

  Map<String, dynamic> toJson() => {
        'display_name': name,
        'goals': goals,
        'assists': assists,
        'penalty_faults': penaltyFaults,
      };
}

class MatchFinalizationContext {
  const MatchFinalizationContext({required this.players});
  final List<PostMatchPlayer> players;
}

class MatchFinalizationRepository {
  MatchFinalizationRepository(this._client);
  final SupabaseClient _client;

  Future<MatchFinalizationContext> fetch(String matchId) async {
    final rows = await _client
        .from('profiles')
        .select('id,first_name,surnom,is_goalkeeper,status')
        .eq('status', 'active')
        .order('first_name');
    final existingRows = await _client
        .from('match_player_stats')
        .select('profile_id,present,goals,assists,penalty_faults,clean_sheet')
        .eq('match_id', matchId);
    final existing = <String, Map<String, dynamic>>{
      for (final row in existingRows as List)
        row['profile_id'].toString(): Map<String, dynamic>.from(row),
    };

    final players = (rows as List).map((raw) {
      final row = Map<String, dynamic>.from(raw);
      final id = row['id'].toString();
      final saved = existing[id] ?? const <String, dynamic>{};
      final nickname = (row['surnom'] ?? '').toString().trim();
      final firstName = (row['first_name'] ?? '').toString().trim();
      return PostMatchPlayer(
        id: id,
        name: nickname.isNotEmpty ? nickname : (firstName.isEmpty ? 'Joueur' : firstName),
        isGoalkeeper: row['is_goalkeeper'] == true,
        present: saved['present'] == true,
        goals: int.tryParse('${saved['goals'] ?? 0}') ?? 0,
        assists: int.tryParse('${saved['assists'] ?? 0}') ?? 0,
        penaltyFaults: int.tryParse('${saved['penalty_faults'] ?? 0}') ?? 0,
        cleanSheet: saved['clean_sheet'] == true,
      );
    }).toList();
    return MatchFinalizationContext(players: players);
  }

  Future<void> finalize({
    required String matchId,
    required int scoreGrinta,
    required int scoreOpponent,
    required String? motmProfileId,
    required List<PostMatchPlayer> players,
    required List<PostMatchGuest> guests,
  }) async {
    final result = await _client.rpc('finalize_match_postgame', params: {
      'p_match_id': matchId,
      'p_score_grinta': scoreGrinta,
      'p_score_adverse': scoreOpponent,
      'p_motm_profile_id': motmProfileId,
      'p_player_stats': players.map((p) => p.toJson()).toList(),
      'p_guest_stats': guests.map((g) => g.toJson()).toList(),
    });
    if (result != true) throw StateError('Le match n’a pas pu être finalisé.');
  }
}

final matchFinalizationRepositoryProvider = Provider<MatchFinalizationRepository>(
  (ref) => MatchFinalizationRepository(ref.watch(supabaseClientProvider)),
);

final matchFinalizationContextProvider =
    FutureProvider.family<MatchFinalizationContext, String>(
  (ref, matchId) => ref.watch(matchFinalizationRepositoryProvider).fetch(matchId),
);
