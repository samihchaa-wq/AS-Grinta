import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/predictions/domain/prediction_scoring.dart';
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
    required this.useX2,
    required this.x2Available,
    required this.oddsWin,
    required this.oddsDraw,
    required this.oddsLoss,
    required this.actualScoreGrinta,
    required this.actualScoreOpponent,
    this.predictionsClosedAt,
  });

  final String matchId;
  final String opponentName;
  final DateTime kickoffAt;
  final String status;
  final int scoreGrinta;
  final int scoreOpponent;
  final bool isFilled;
  final bool useX2;
  final int x2Available;
  final double? oddsWin;
  final double? oddsDraw;
  final double? oddsLoss;
  final int? actualScoreGrinta;
  final int? actualScoreOpponent;
  final DateTime? predictionsClosedAt;

  DateTime get closesAt => kickoffAt.subtract(const Duration(minutes: 5));

  bool isClosedAt(DateTime now) =>
      status != 'a_venir' ||
      !now.isBefore(closesAt) ||
      (predictionsClosedAt != null && !now.isBefore(predictionsClosedAt!));

  bool canEditAt(DateTime now) => !isClosedAt(now);
  bool get isClosed => isClosedAt(DateTime.now());
  bool get canEdit => canEditAt(DateTime.now());
  bool get hasResult =>
      actualScoreGrinta != null && actualScoreOpponent != null;

  double? get earnedPoints {
    if (!isFilled || !hasResult) return hasResult ? 0 : null;
    final actualResult = _result(actualScoreGrinta!, actualScoreOpponent!);
    final decimalOdds = switch (actualResult) {
      1 => oddsWin,
      0 => oddsDraw,
      _ => oddsLoss,
    };
    final points = PredictionScoring.points(
      predictedHome: scoreGrinta,
      predictedAway: scoreOpponent,
      actualHome: actualScoreGrinta!,
      actualAway: actualScoreOpponent!,
      baseOdds: decimalOdds,
    );
    return points == null ? null : points * (useX2 ? 2 : 1);
  }

  static int _result(int grinta, int opponent) {
    if (grinta > opponent) return 1;
    if (grinta == opponent) return 0;
    return -1;
  }
}

class PredictionsRepository {
  PredictionsRepository(this._client);

  final SupabaseClient _client;

  static const _matchSelect = '''
    id,
    match_date,
    match_time,
    status,
    score_as_grinta,
    score_adverse,
    predictions_closed_at,
    opponents(name),
    match_odds(
      odds_victoire_as_grinta,
      odds_nul,
      odds_victoire_adverse
    )
  ''';

  Future<List<MatchPredictionItem>> fetchMyMatchPredictions() async {
    final matches = await _client
        .from('matches')
        .select(_matchSelect)
        .eq('status', 'a_venir')
        .order('match_date', ascending: true)
        .order('match_time', ascending: true);
    final items = <MatchPredictionItem>[];
    for (final match in matches as List) {
      items.add(
        await _buildItem(Map<String, dynamic>.from(match as Map)),
      );
    }
    return items;
  }

  Future<MatchPredictionItem?> fetchMatchPrediction(String matchId) async {
    final match = await _client
        .from('matches')
        .select(_matchSelect)
        .eq('id', matchId)
        .maybeSingle();
    if (match == null) return null;
    return _buildItem(Map<String, dynamic>.from(match));
  }

  Future<MatchPredictionItem> _buildItem(Map<String, dynamic> matchMap) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utilisateur non authentifié.');
    final matchId = matchMap['id'].toString();
    final prediction = await _client
        .from('match_predictions')
        .select(
          'match_id, predicted_score_as_grinta, predicted_score_adverse, is_filled, use_x2',
        )
        .eq('profile_id', userId)
        .eq('match_id', matchId)
        .maybeSingle();
    final wallet = await _client
        .from('v_x2_wallet')
        .select('available_count')
        .eq('profile_id', userId)
        .maybeSingle();

    final date = matchMap['match_date']?.toString() ?? '';
    final time = matchMap['match_time']?.toString() ?? '00:00:00';
    final kickoffAt = DateTime.tryParse('${date}T$time') ?? DateTime(1970);
    final opponent = matchMap['opponents'] is Map
        ? Map<String, dynamic>.from(matchMap['opponents'] as Map)
        : const <String, dynamic>{};
    final oddsRaw = matchMap['match_odds'];
    final odds = oddsRaw is List && oddsRaw.isNotEmpty
        ? Map<String, dynamic>.from(oddsRaw.first as Map)
        : oddsRaw is Map
            ? Map<String, dynamic>.from(oddsRaw)
            : const <String, dynamic>{};

    return MatchPredictionItem(
      matchId: matchId,
      opponentName: opponent['name']?.toString() ?? 'Adversaire',
      kickoffAt: kickoffAt,
      status: matchMap['status']?.toString() ?? 'a_venir',
      scoreGrinta:
          int.tryParse('${prediction?['predicted_score_as_grinta'] ?? 0}') ?? 0,
      scoreOpponent:
          int.tryParse('${prediction?['predicted_score_adverse'] ?? 0}') ?? 0,
      isFilled: prediction?['is_filled'] == true,
      useX2: prediction?['use_x2'] == true,
      x2Available: (wallet?['available_count'] as num?)?.toInt() ?? 0,
      oddsWin: (odds['odds_victoire_as_grinta'] as num?)?.toDouble(),
      oddsDraw: (odds['odds_nul'] as num?)?.toDouble(),
      oddsLoss: (odds['odds_victoire_adverse'] as num?)?.toDouble(),
      actualScoreGrinta: matchMap['score_as_grinta'] == null
          ? null
          : int.tryParse('${matchMap['score_as_grinta']}'),
      actualScoreOpponent: matchMap['score_adverse'] == null
          ? null
          : int.tryParse('${matchMap['score_adverse']}'),
      predictionsClosedAt: DateTime.tryParse(
        '${matchMap['predictions_closed_at'] ?? ''}',
      ),
    );
  }

  Future<void> savePrediction({
    required String matchId,
    required int scoreGrinta,
    required int scoreOpponent,
    required bool useX2,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utilisateur non authentifié.');
    if (scoreGrinta < 0 ||
        scoreGrinta > 99 ||
        scoreOpponent < 0 ||
        scoreOpponent > 99) {
      throw ArgumentError('Les scores doivent être compris entre 0 et 99.');
    }

    final match = await _client
        .from('matches')
        .select('match_date, match_time, status')
        .eq('id', matchId)
        .maybeSingle();
    if (match == null) {
      throw StateError('Ce match est introuvable ou a été supprimé.');
    }
    final kickoffAt = DateTime.tryParse(
      '${match['match_date']}T${match['match_time']}',
    );
    if (kickoffAt == null || match['status'] != 'a_venir') {
      throw StateError('Ce pronostic est fermé.');
    }
    if (!DateTime.now().isBefore(
      kickoffAt.subtract(const Duration(minutes: 5)),
    )) {
      throw StateError('Ce pronostic est fermé.');
    }

    await _client.from('match_predictions').upsert({
      'match_id': matchId,
      'profile_id': userId,
      'predicted_score_as_grinta': scoreGrinta,
      'predicted_score_adverse': scoreOpponent,
      'is_filled': true,
      'use_x2': useX2,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'match_id,profile_id');
  }
}

final predictionsRepositoryProvider = Provider<PredictionsRepository>((ref) {
  return PredictionsRepository(ref.watch(supabaseClientProvider));
});
