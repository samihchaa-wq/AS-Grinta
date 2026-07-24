import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InternalMatchPlayer {
  const InternalMatchPlayer({
    required this.seasonPlayerId,
    required this.name,
    required this.teamNo,
    required this.sortOrder,
    required this.isGoalkeeper,
    this.photoUrl,
  });

  final String seasonPlayerId;
  final String name;
  final int teamNo;
  final int sortOrder;
  final bool isGoalkeeper;
  final String? photoUrl;
}

class InternalMatch {
  const InternalMatch({
    required this.id,
    required this.seasonId,
    required this.kickoffAt,
    required this.teamAName,
    required this.teamBName,
    required this.status,
    required this.players,
    this.address,
    this.scoreA,
    this.scoreB,
  });

  final String id;
  final String seasonId;
  final DateTime kickoffAt;
  final String teamAName;
  final String teamBName;
  final String status;
  final String? address;
  final int? scoreA;
  final int? scoreB;
  final List<InternalMatchPlayer> players;

  bool get isFinished => status == 'termine';

  List<InternalMatchPlayer> get teamAPlayers =>
      players.where((player) => player.teamNo == 1).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<InternalMatchPlayer> get teamBPlayers =>
      players.where((player) => player.teamNo == 2).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
}

class InternalMatchAssignment {
  const InternalMatchAssignment({
    required this.seasonPlayerId,
    required this.teamNo,
    required this.sortOrder,
  });

  final String seasonPlayerId;
  final int teamNo;
  final int sortOrder;

  Map<String, dynamic> toJson() => {
        'season_player_id': seasonPlayerId,
        'team_no': teamNo,
        'sort_order': sortOrder,
      };
}

class InternalMatchesRepository {
  InternalMatchesRepository(this._client);

  final SupabaseClient _client;

  Future<List<InternalMatch>> fetchAll() async {
    final rows = await _client.from('internal_matches').select('''
      id,
      season_id,
      kickoff_at,
      address,
      team_a_name,
      team_b_name,
      score_a,
      score_b,
      status,
      internal_match_players(
        season_player_id,
        team_no,
        sort_order,
        season_players(
          id,
          first_name,
          last_name,
          is_goalkeeper,
          photo_url
        )
      )
    ''').order('kickoff_at', ascending: true);

    return (rows as List)
        .map((row) => _fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<String> save({
    String? matchId,
    required String seasonId,
    required DateTime kickoffAt,
    required String teamAName,
    required String teamBName,
    required List<InternalMatchAssignment> players,
    String? address,
    int? scoreA,
    int? scoreB,
  }) async {
    final result = await _client.rpc(
      'admin_save_internal_match',
      params: {
        'p_match_id': matchId,
        'p_season_id': seasonId,
        'p_kickoff_at': kickoffAt.toUtc().toIso8601String(),
        'p_address': address,
        'p_team_a_name': teamAName,
        'p_team_b_name': teamBName,
        'p_score_a': scoreA,
        'p_score_b': scoreB,
        'p_players': players.map((player) => player.toJson()).toList(),
      },
    );
    final id = result?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('Le match entre nous n’a pas pu être enregistré.');
    }
    return id;
  }

  Future<void> delete(String matchId) async {
    final result = await _client.rpc(
      'admin_delete_internal_match',
      params: {'p_match_id': matchId},
    );
    if (result != true) {
      throw StateError('Le match entre nous n’a pas pu être supprimé.');
    }
  }

  InternalMatch _fromJson(Map<String, dynamic> json) {
    final playersRaw = json['internal_match_players'];
    final players = playersRaw is List
        ? playersRaw.whereType<Map>().map((raw) {
            final item = Map<String, dynamic>.from(raw);
            final playerRaw = item['season_players'];
            final player = playerRaw is Map
                ? Map<String, dynamic>.from(playerRaw)
                : const <String, dynamic>{};
            final firstName = (player['first_name'] ?? '').toString().trim();
            final lastName = (player['last_name'] ?? '').toString().trim();
            final name = firstName.isNotEmpty
                ? firstName
                : lastName.isNotEmpty
                    ? lastName
                    : 'Joueur';
            final photo = player['photo_url']?.toString().trim();
            return InternalMatchPlayer(
              seasonPlayerId: item['season_player_id'].toString(),
              name: name,
              teamNo: (item['team_no'] as num?)?.toInt() ?? 1,
              sortOrder: (item['sort_order'] as num?)?.toInt() ?? 0,
              isGoalkeeper: player['is_goalkeeper'] == true,
              photoUrl: photo == null || photo.isEmpty ? null : photo,
            );
          }).toList()
        : <InternalMatchPlayer>[];

    return InternalMatch(
      id: json['id'].toString(),
      seasonId: json['season_id'].toString(),
      kickoffAt: DateTime.parse(json['kickoff_at'].toString()).toLocal(),
      address: _optionalText(json['address']),
      teamAName: (json['team_a_name'] ?? 'Les Verts').toString(),
      teamBName: (json['team_b_name'] ?? 'Les Bleus').toString(),
      scoreA: (json['score_a'] as num?)?.toInt(),
      scoreB: (json['score_b'] as num?)?.toInt(),
      status: (json['status'] ?? 'a_venir').toString(),
      players: players,
    );
  }

  String? _optionalText(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

final internalMatchesRepositoryProvider = Provider<InternalMatchesRepository>(
  (ref) => InternalMatchesRepository(ref.watch(supabaseClientProvider)),
);

final internalMatchesProvider = FutureProvider<List<InternalMatch>>(
  (ref) => ref.watch(internalMatchesRepositoryProvider).fetchAll(),
);
