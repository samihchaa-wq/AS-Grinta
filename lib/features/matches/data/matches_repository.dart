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
      kickoff_at,
      location,
      planned_duration_minutes,
      status,
      score_as_grinta,
      score_adverse,
      predictions_closed_at,
      address,
      created_by,
      created_at,
      updated_at,
      opponents(name),
      seasons(name),
      match_odds(
        odds_victoire_as_grinta,
        odds_nul,
        odds_victoire_adverse
      )
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
    final response = await _client
        .from('opponents')
        .select('id, name, address')
        .order('name');
    return (response as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  /// Adresse du terrain d'AS Grinta (mémorisée pour les matchs à domicile).
  Future<String?> fetchClubHomeAddress() async {
    final row = await _client
        .from('club_settings')
        .select('home_address')
        .maybeSingle();
    final value = row?['home_address']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// Enregistre l'adresse d'un match ; elle est mémorisée sur l'équipe à
  /// domicile pour préremplir les prochaines rencontres.
  Future<void> setMatchAddress({
    required String matchId,
    required String? address,
  }) async {
    await _client.rpc(
      'admin_set_match_address',
      params: {'p_match_id': matchId, 'p_address': address},
    );
  }

  Future<String> createOpponent(String name) async {
    final result = await _client.rpc(
      'get_or_create_opponent',
      params: {'p_name': name.trim()},
    );
    if (result == null || result.toString().isEmpty) {
      throw StateError('L’adversaire n’a pas pu être créé.');
    }
    return result.toString();
  }

  /// Crée le match et renvoie son identifiant.
  Future<String> createMatch({
    required String seasonId,
    required String opponentId,
    required DateTime kickoffAt,
    required bool isHome,
    required double oddsWin,
    required double oddsDraw,
    required double oddsLoss,
    int? squadSizeLimit,
  }) async {
    final sportsEnabled = squadSizeLimit != null;
    final result = await _client.rpc(
      sportsEnabled
          ? 'create_match_with_odds_and_sport_limit'
          : 'create_match_with_odds',
      params: {
        'p_season_id': seasonId,
        'p_opponent_id': opponentId,
        'p_match_date': kickoffAt.toIso8601String().split('T').first,
        'p_match_time': _formatTime(kickoffAt),
        'p_location': isHome ? 'domicile' : 'exterieur',
        'p_win': oddsWin,
        'p_draw': oddsDraw,
        'p_loss': oddsLoss,
        if (sportsEnabled) 'p_squad_size_limit': squadSizeLimit,
      },
    );
    if (result == null || result.toString().isEmpty) {
      throw StateError('Le match n’a pas pu être créé.');
    }
    return result.toString();
  }

  /// Cotes suggérées par le modèle historique (V2.1) pour un adversaire et
  /// un lieu donnés. Retourne null si le calcul échoue.
  Future<({double win, double draw, double loss})?> previewMatchOdds({
    required String opponentId,
    required bool isHome,
  }) async {
    try {
      final result = await _client.rpc(
        'preview_match_odds',
        params: {
          'p_opponent_id': opponentId,
          'p_location': isHome ? 'domicile' : 'exterieur',
        },
      );
      if (result is! Map) return null;
      final map = Map<String, dynamic>.from(result);
      final win = (map['win'] as num?)?.toDouble();
      final draw = (map['draw'] as num?)?.toDouble();
      final loss = (map['loss'] as num?)?.toDouble();
      if (win == null || draw == null || loss == null) return null;
      return (win: win, draw: draw, loss: loss);
    } catch (_) {
      return null;
    }
  }

  Future<void> updateMatch({
    required String id,
    required String seasonId,
    required String opponentId,
    required DateTime kickoffAt,
    required bool isHome,
    required String status,
    required double oddsWin,
    required double oddsDraw,
    required double oddsLoss,
    int? squadSizeLimit,
  }) async {
    final sportsEnabled = squadSizeLimit != null;
    final result = await _client.rpc(
      sportsEnabled
          ? 'update_match_with_odds_and_sport_limit'
          : 'update_match_with_odds',
      params: {
        'p_match_id': id,
        'p_season_id': seasonId,
        'p_opponent_id': opponentId,
        'p_match_date': kickoffAt.toIso8601String().split('T').first,
        'p_match_time': _formatTime(kickoffAt),
        'p_location': isHome ? 'domicile' : 'exterieur',
        'p_status': status,
        'p_win': oddsWin,
        'p_draw': oddsDraw,
        'p_loss': oddsLoss,
        if (sportsEnabled) 'p_squad_size_limit': squadSizeLimit,
      },
    );
    if (result != true) {
      throw StateError('Le match et ses cotes n’ont pas pu être enregistrés.');
    }
  }

  Future<int> fetchSportSquadLimit(String matchId) async {
    final response = await _client.rpc(
      'admin_get_match_convocations',
      params: {'p_match_id': matchId},
    );
    if (response is! Map) {
      throw const FormatException('Configuration sportive invalide.');
    }
    return (response['squad_size_limit'] as num?)?.toInt() ?? 14;
  }

  Future<void> deleteMatch(String id) async {
    final result = await _client.rpc(
      'delete_match',
      params: {'p_match_id': id},
    );
    if (result != true) {
      throw StateError('Le match n’existe plus ou n’a pas pu être supprimé.');
    }
  }

  Future<void> finalizeMatchPostgame({
    required String id,
    required int grintaScore,
    required int opponentScore,
    required List<Map<String, dynamic>> scorers,
    required String? cleanSheetProfileId,
    required List<String> presentPlayerIds,
    required String? manOfMatchPlayerId,
  }) async {
    final result = await _client.rpc(
      'finalize_match_postgame_with_lineup',
      params: {
        'p_match_id': id,
        'p_score_adverse': opponentScore,
        'p_scorers': scorers,
        'p_clean_sheet_player_id': cleanSheetProfileId,
        'p_score_as_grinta': grintaScore,
        'p_present': presentPlayerIds,
        'p_man_of_match_player_id': manOfMatchPlayerId,
      },
    );
    if (result != true) {
      throw StateError('Le match n’a pas pu être validé.');
    }
  }

  Future<void> closeMatchPredictions(String id) async {
    final result = await _client.rpc(
      'close_match_predictions',
      params: {'p_match_id': id},
    );
    if (result != true) {
      throw StateError('Les pronostics n’ont pas pu être fermés.');
    }
  }

  Future<Map<String, double>?> fetchMatchOdds(String matchId) async {
    final response = await _client
        .from('match_odds')
        .select('odds_victoire_as_grinta, odds_nul, odds_victoire_adverse')
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
        .select(
          'match_id,profile_id,predicted_score_as_grinta,predicted_score_adverse,is_filled,updated_at',
        )
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
