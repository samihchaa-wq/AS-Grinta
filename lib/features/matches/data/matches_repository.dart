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
        .order('match_date', ascending: true)
        .order('match_time', ascending: true);
    return (response as List)
        .map((row) => MatchModel.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchSeasons() async {
    final response =
        await _client.from('seasons').select('id, name').order('name');
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

  Future<void> createMatch({
    required String seasonId,
    required String opponentId,
    required DateTime kickoffAt,
    required bool isHome,
    required int plannedDurationMinutes,
    required String status,
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
      'planned_duration_minutes': plannedDurationMinutes,
      'status': status,
      'created_by': currentUserId,
    });
  }

  Future<void> updateMatch({
    required String id,
    required String seasonId,
    required String opponentId,
    required DateTime kickoffAt,
    required bool isHome,
    required int plannedDurationMinutes,
    required String status,
  }) async {
    await _client.from('matches').update({
      'season_id': seasonId,
      'opponent_id': opponentId,
      'match_date': kickoffAt.toIso8601String().split('T').first,
      'match_time': _formatTime(kickoffAt),
      'location': isHome ? 'domicile' : 'exterieur',
      'planned_duration_minutes': plannedDurationMinutes,
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> deleteMatch(String id) async {
    await _client.from('matches').delete().eq('id', id);
  }

  Future<void> finalizeMatch({
    required String id,
    required int grintaScore,
    required int opponentScore,
    required String status,
    required String? manOfTheMatchId,
  }) async {
    await _client.from('matches').update({
      'score_as_grinta': grintaScore,
      'score_adverse': opponentScore,
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);

    await _client.from('live_sessions').update({
      'status': 'finished',
      'controller_profile_id': null,
      'controller_session_id': null,
      'controller_disconnected_at': null,
      'clock_started_at': null,
    }).eq('match_id', id);

    await _client.from('match_motm').delete().eq('match_id', id);
    if (manOfTheMatchId != null && manOfTheMatchId.isNotEmpty) {
      final currentUserId = _client.auth.currentUser?.id;
      if (currentUserId == null) {
        throw StateError('Utilisateur non authentifié.');
      }
      await _client.from('match_motm').insert({
        'match_id': id,
        'profile_id': manOfTheMatchId,
        'created_by': currentUserId,
      });
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

  Future<void> updateMatchScore({
    required String id,
    required int grintaScore,
    required int opponentScore,
  }) async {
    await _client.from('matches').update({
      'score_as_grinta': grintaScore,
      'score_adverse': opponentScore,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> updateMatchStatus({
    required String id,
    required String status,
  }) async {
    await _client.from('matches').update({
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
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
