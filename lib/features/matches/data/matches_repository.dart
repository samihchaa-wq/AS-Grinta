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
    final response = await _client.from('seasons').select('id, name').order('name');
    return (response as List).map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchOpponents() async {
    final response = await _client.from('opponents').select('id, name').order('name');
    return (response as List).map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> createMatch({
    required String seasonId,
    required String opponentId,
    required DateTime kickoffAt,
    required bool isHome,
    required int plannedDurationMinutes,
    required String status,
  }) async {
    await _client.from('matches').insert({
      'season_id': seasonId,
      'opponent_id': opponentId,
      'match_date': kickoffAt.toIso8601String().split('T').first,
      'match_time': _formatTime(kickoffAt),
      'location': isHome ? 'domicile' : 'exterieur',
      'planned_duration_minutes': plannedDurationMinutes,
      'status': status,
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
  }) async {
    await _client.from('matches').update({
      'score_as_grinta': grintaScore,
      'score_adverse': opponentScore,
      'status': status,
    }).eq('id', id);
  }

  Future<void> updateMatchScore({
    required String id,
    required int grintaScore,
    required int opponentScore,
  }) async {
    await _client.from('matches').update({
      'score_as_grinta': grintaScore,
      'score_adverse': opponentScore,
    }).eq('id', id);
  }

  Future<void> updateMatchStatus({
    required String id,
    required String status,
  }) async {
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
