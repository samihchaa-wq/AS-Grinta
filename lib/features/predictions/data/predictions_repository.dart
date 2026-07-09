import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MatchPredictionItem {
  const MatchPredictionItem({
    required this.matchId,
    required this.opponentName,
    required this.kickoffAt,
    required this.status,
    required this.scoreGrinta,
    required this.scoreOpponent,
    required this.isFilled,
    required this.oddsWin,
    required this.oddsDraw,
    required this.oddsLoss,
  });

  final String matchId;
  final String opponentName;
  final DateTime kickoffAt;
  final String status;
  final int scoreGrinta;
  final int scoreOpponent;
  final bool isFilled;
  final double? oddsWin;
  final double? oddsDraw;
  final double? oddsLoss;

  bool get isClosed =>
      status != 'a_venir' || DateTime.now().isAfter(kickoffAt.subtract(const Duration(hours: 12)));

  MatchPredictionItem copyWith({
    int? scoreGrinta,
    int? scoreOpponent,
    bool? isFilled,
  }) {
    return MatchPredictionItem(
      matchId: matchId,
      opponentName: opponentName,
      kickoffAt: kickoffAt,
      status: status,
      scoreGrinta: scoreGrinta ?? this.scoreGrinta,
      scoreOpponent: scoreOpponent ?? this.scoreOpponent,
      isFilled: isFilled ?? this.isFilled,
      oddsWin: oddsWin,
      oddsDraw: oddsDraw,
      oddsLoss: oddsLoss,
    );
  }
}

class PredictionsRepository {
  PredictionsRepository(this._client);

  final SupabaseClient _client;

  Future<List<MatchPredictionItem>> fetchMyMatchPredictions() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utilisateur non authentifié.');

    final matches = await _client
        .from('matches')
        .select('''
          id,
          match_date,
          match_time,
          status,
          opponents(name),
          match_odds(
            odds_victoire_as_grinta,
            odds_nul,
            odds_victoire_adverse
          )
        ''')
        .neq('status', 'archive')
        .order('match_date', ascending: true)
        .order('match_time', ascending: true);

    final predictions = await _client
        .from('match_predictions')
        .select('match_id, predicted_score_as_grinta, predicted_score_adverse, is_filled')
        .eq('profile_id', userId);

    final byMatch = <String, Map<String, dynamic>>{};
    for (final row in predictions as List) {
      final map = Map<String, dynamic>.from(row);
      byMatch[map['match_id'].toString()] = map;
    }

    return (matches as List).map((row) {
      final map = Map<String, dynamic>.from(row);
      final id = map['id'].toString();
      final prediction = byMatch[id];
      final date = map['match_date']?.toString() ?? '';
      final time = map['match_time']?.toString() ?? '00:00:00';
      final kickoffAt = DateTime.tryParse('${date}T$time') ?? DateTime(1970);
      final opponent = map['opponents'] is Map
          ? Map<String, dynamic>.from(map['opponents'] as Map)
          : const <String, dynamic>{};
      final oddsRaw = map['match_odds'];
      final odds = oddsRaw is List && oddsRaw.isNotEmpty
          ? Map<String, dynamic>.from(oddsRaw.first as Map)
          : oddsRaw is Map
              ? Map<String, dynamic>.from(oddsRaw)
              : const <String, dynamic>{};

      return MatchPredictionItem(
        matchId: id,
        opponentName: opponent['name']?.toString() ?? 'Adversaire',
        kickoffAt: kickoffAt,
        status: map['status']?.toString() ?? 'a_venir',
        scoreGrinta: int.tryParse('${prediction?['predicted_score_as_grinta'] ?? 0}') ?? 0,
        scoreOpponent: int.tryParse('${prediction?['predicted_score_adverse'] ?? 0}') ?? 0,
        isFilled: prediction?['is_filled'] == true,
        oddsWin: (odds['odds_victoire_as_grinta'] as num?)?.toDouble(),
        oddsDraw: (odds['odds_nul'] as num?)?.toDouble(),
        oddsLoss: (odds['odds_victoire_adverse'] as num?)?.toDouble(),
      );
    }).toList();
  }

  Future<void> savePrediction({
    required String matchId,
    required int scoreGrinta,
    required int scoreOpponent,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utilisateur non authentifié.');
    if (scoreGrinta < 0 || scoreGrinta > 99 || scoreOpponent < 0 || scoreOpponent > 99) {
      throw ArgumentError('Les scores doivent être compris entre 0 et 99.');
    }

    await _client.from('match_predictions').upsert(
      {
        'match_id': matchId,
        'profile_id': userId,
        'predicted_score_as_grinta': scoreGrinta,
        'predicted_score_adverse': scoreOpponent,
        'is_filled': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'match_id,profile_id',
    );
  }
}

final predictionsRepositoryProvider = Provider<PredictionsRepository>((ref) {
  return PredictionsRepository(ref.watch(supabaseClientProvider));
});
