import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MatchesRepository {
  MatchesRepository(this._client);

  final SupabaseClient _client;

  Future<List<MatchModel>> fetchMatches({String? seasonId}) async {
    var query = _client.from('matches').select('''
      id,
      season_id,
      opponent_id,
      match_date,
      match_time,
      location,
      competition,
      planned_duration_minutes,
      status,
      score_as_grinta,
      score_adverse,
      created_by,
      created_at,
      updated_at,
      opponents(name),
      seasons(name)
    ''');

    if (seasonId != null && seasonId.isNotEmpty) {
      query = query.eq('season_id', seasonId);
    }

    final response = await query
        .order('match_date', ascending: false)
        .order('match_time', ascending: false);
    return (response as List)
        .map((row) => MatchModel.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchSeasons() async {
    final response =
        await _client.from('seasons').select('id, name, status').order('name');
    return (response as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchOpponents() async {
    final response =
        await _client.from('opponents').select('id, name').order('name');
    return (response as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<String> createOpponent(String name) async {
    final existing = await _client
        .from('opponents')
        .select('id')
        .ilike('name', name)
        .maybeSingle();
    if (existing != null) return existing['id'].toString();

    final response = await _client
        .from('opponents')
        .insert({'name': name})
        .select('id')
        .single();
    return response['id'].toString();
  }

  Future<void> createMatch({
    required String seasonId,
    required String opponentId,
    required DateTime kickoffAt,
    required bool isHome,
    required String competition,
  }) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) {
      throw StateError('Utilisateur non authentifié.');
    }

    await _client.from('matches').insert({
      'season_id': seasonId,
      'opponent_id': opponentId,
      'match_date': kickoffAt.toIso8601String().split('T').first,
      'match_time': _formatTime(kickoffAt),
      'location': isHome ? 'domicile' : 'exterieur',
      'competition': competition.trim(),
      'planned_duration_minutes': 90,
      'status': 'a_venir',
      'created_by': currentUserId,
    });
  }

  Future<void> updateMatch({
    required String id,
    required String seasonId,
    required String opponentId,
    required DateTime kickoffAt,
    required bool isHome,
    required String competition,
    required String status,
  }) async {
    await _client.from('matches').update({
      'season_id': seasonId,
      'opponent_id': opponentId,
      'match_date': kickoffAt.toIso8601String().split('T').first,
      'match_time': _formatTime(kickoffAt),
      'location': isHome ? 'domicile' : 'exterieur',
      'competition': competition.trim(),
      'status': status,
    }).eq('id', id);
  }

  Future<void> deleteMatch(String id) async {
    await _client.from('matches').delete().eq('id', id);
  }

  Future<void> finalizeMatchPostgame({
    required String id,
    required int opponentScore,
    required String? manOfTheMatchId,
    required List<Map<String, dynamic>> playerStats,
    required List<Map<String, dynamic>> guestStats,
  }) async {
    final result = await _client.rpc(
      'finalize_match_postgame',
      params: {
        'p_match_id': id,
        'p_score_grinta': 0,
        'p_score_adverse': opponentScore,
        'p_motm_profile_id': manOfTheMatchId,
        'p_player_stats': playerStats,
        'p_guest_stats': guestStats,
      },
    );
    if (result != true) {
      throw StateError('Le match n’a pas pu être validé.');
    }
  }

  Future<Map<String, double>?> fetchMatchOdds(String matchId) async {
    final response = await _client
        .from('match_odds')
        .select(
          'odds_victoire_as_grinta, odds_nul, odds_victoire_adverse',
        )
        .eq('match_id', matchId)
        .maybeSingle();
    if (response == null) return null;
    return {
      'win': (response['odds_victoire_as_grinta'] as num).toDouble(),
      'draw': (response['odds_nul'] as num).toDouble(),
      'loss': (response['odds_victoire_adverse'] as num).toDouble(),
    };
  }

  Future<int> fetchPredictionParticipantCount(String matchId) async {
    final result = await _client.rpc(
      'match_prediction_participant_count',
      params: {'p_match_id': matchId},
    );
    return (result as num?)?.toInt() ?? 0;
  }

  Future<List<Map<String, dynamic>>> fetchMatchPredictions(
    String matchId,
  ) async {
    final response = await _client
        .from('match_predictions')
        .select()
        .eq('match_id', matchId)
        .eq('is_filled', true);
    return (response as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> updateMatchStatus({
    required String id,
    required String status,
  }) async {
    if (status == 'archive') {
      final result = await _client.rpc(
        'archive_match',
        params: {'p_match_id': id},
      );
      if (result != true) {
        throw StateError('Le match n’a pas pu être archivé.');
      }
      return;
    }

    await _client.from('matches').update({'status': status}).eq('id', id);
  }

  String _formatTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }
}

final matchesRepositoryProvider = Provider<MatchesRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return MatchesRepository(client);
});
