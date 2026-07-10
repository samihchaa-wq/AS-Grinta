import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HeadToHeadMatch {
  const HeadToHeadMatch({
    required this.date,
    required this.location,
    required this.scoreGrinta,
    required this.scoreOpponent,
  });

  final DateTime date;
  final String location;
  final int? scoreGrinta;
  final int? scoreOpponent;
}

class MatchDetailsData {
  const MatchDetailsData({
    required this.matchId,
    required this.opponentId,
    required this.opponentName,
    required this.kickoffAt,
    required this.status,
    required this.competition,
    required this.location,
    required this.scoreGrinta,
    required this.scoreOpponent,
    required this.oddsWin,
    required this.oddsDraw,
    required this.oddsLoss,
    required this.predictionParticipantCount,
    required this.headToHead,
  });

  final String matchId;
  final String opponentId;
  final String opponentName;
  final DateTime kickoffAt;
  final String status;
  final String competition;
  final String location;
  final int? scoreGrinta;
  final int? scoreOpponent;
  final double? oddsWin;
  final double? oddsDraw;
  final double? oddsLoss;
  final int predictionParticipantCount;
  final List<HeadToHeadMatch> headToHead;
}

class MatchDetailsRepository {
  MatchDetailsRepository(this._client);

  final SupabaseClient _client;

  Future<MatchDetailsData> fetch(String matchId) async {
    final match = await _client.from('matches').select('''
      id,
      opponent_id,
      match_date,
      match_time,
      status,
      competition,
      location,
      score_as_grinta,
      score_adverse,
      opponents(name),
      match_odds(
        odds_victoire_as_grinta,
        odds_nul,
        odds_victoire_adverse
      )
    ''').eq('id', matchId).single();
    final opponentId = match['opponent_id'].toString();
    final opponent = Map<String, dynamic>.from(match['opponents'] as Map);
    final kickoffAt = DateTime.tryParse(
          '${match['match_date']}T${match['match_time']}',
        ) ??
        DateTime(1970);
    final oddsRaw = match['match_odds'];
    final odds = oddsRaw is List && oddsRaw.isNotEmpty
        ? Map<String, dynamic>.from(oddsRaw.first as Map)
        : oddsRaw is Map
            ? Map<String, dynamic>.from(oddsRaw)
            : const <String, dynamic>{};
    final countResult = await _client.rpc(
      'match_prediction_participant_count',
      params: {'p_match_id': matchId},
    );

    final historyRaw = await _client
        .from('matches')
        .select('match_date, location, score_as_grinta, score_adverse')
        .eq('opponent_id', opponentId)
        .neq('id', matchId)
        .inFilter('status', ['termine', 'archive'])
        .order('match_date', ascending: false)
        .limit(5);
    final history = (historyRaw as List)
        .map((row) => Map<String, dynamic>.from(row))
        .map(
          (row) => HeadToHeadMatch(
            date: DateTime.tryParse(row['match_date'].toString()) ??
                DateTime(1970),
            location: row['location'].toString(),
            scoreGrinta: row['score_as_grinta'] == null
                ? null
                : int.tryParse('${row['score_as_grinta']}'),
            scoreOpponent: row['score_adverse'] == null
                ? null
                : int.tryParse('${row['score_adverse']}'),
          ),
        )
        .toList();

    return MatchDetailsData(
      matchId: matchId,
      opponentId: opponentId,
      opponentName: opponent['name']?.toString() ?? 'Adversaire',
      kickoffAt: kickoffAt,
      status: match['status']?.toString() ?? 'a_venir',
      competition: (match['competition'] ?? 'Championnat').toString(),
      location: (match['location'] ?? 'domicile').toString(),
      scoreGrinta: match['score_as_grinta'] == null
          ? null
          : int.tryParse('${match['score_as_grinta']}'),
      scoreOpponent: match['score_adverse'] == null
          ? null
          : int.tryParse('${match['score_adverse']}'),
      oddsWin: (odds['odds_victoire_as_grinta'] as num?)?.toDouble(),
      oddsDraw: (odds['odds_nul'] as num?)?.toDouble(),
      oddsLoss: (odds['odds_victoire_adverse'] as num?)?.toDouble(),
      predictionParticipantCount: (countResult as num?)?.toInt() ?? 0,
      headToHead: history,
    );
  }

  Future<void> reportMatch({
    required String matchId,
    required DateTime kickoffAt,
  }) async {
    await _client.from('matches').update({
      'match_date': kickoffAt.toIso8601String().split('T').first,
      'match_time': _formatTime(kickoffAt),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', matchId);
  }

  String _formatTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }
}

final matchDetailsRepositoryProvider = Provider<MatchDetailsRepository>((ref) {
  return MatchDetailsRepository(ref.watch(supabaseClientProvider));
});

final matchDetailsProvider =
    FutureProvider.family<MatchDetailsData, String>((ref, matchId) {
  return ref.watch(matchDetailsRepositoryProvider).fetch(matchId);
});
