import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/utils/match_window.dart';
import 'package:as_grinta/features/predictions/domain/prediction_scoring.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MatchPredictionItem {
  const MatchPredictionItem({
    required this.matchId,
    required this.opponentName,
    required this.kickoffAt,
    required this.status,
    this.isHome = true,
    required this.scoreGrinta,
    required this.scoreOpponent,
    required this.isFilled,
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
  final bool isHome;
  final int scoreGrinta;
  final int scoreOpponent;
  final bool isFilled;
  final double? oddsWin;
  final double? oddsDraw;
  final double? oddsLoss;
  final int? actualScoreGrinta;
  final int? actualScoreOpponent;
  final DateTime? predictionsClosedAt;

  DateTime get opensAt => matchFeaturesOpenAt(kickoffAt);
  DateTime get closesAt => kickoffAt.subtract(const Duration(minutes: 5));

  bool isClosedAt(DateTime now) =>
      status != 'a_venir' ||
      now.isBefore(opensAt) ||
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
    return PredictionScoring.points(
      predictedHome: scoreGrinta,
      predictedAway: scoreOpponent,
      actualHome: actualScoreGrinta!,
      actualAway: actualScoreOpponent!,
      baseOdds: decimalOdds,
    );
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
    kickoff_at,
    status,
    location,
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

  static const _predictionSelect =
      'match_id, predicted_score_as_grinta, predicted_score_adverse, is_filled';

  Future<List<MatchPredictionItem>> fetchMyMatchPredictions() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utilisateur non authentifié.');
    final response = await _client
        .from('matches')
        .select(_matchSelect)
        .eq('status', 'a_venir')
        .neq('match_type', 'entre_nous')
        .order('kickoff_at', ascending: true);
    final matches = (response as List)
        .map((match) => Map<String, dynamic>.from(match as Map))
        .toList();
    final matchIds = [for (final match in matches) match['id'].toString()];

    final predictionsById = <String, Map<String, dynamic>>{};
    if (matchIds.isNotEmpty) {
      final predRows = await _client
          .from('match_predictions')
          .select(_predictionSelect)
          .eq('profile_id', userId)
          .inFilter('match_id', matchIds);
      for (final row in predRows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        predictionsById[map['match_id'].toString()] = map;
      }
    }

    return [
      for (final match in matches)
        _buildItem(match, prediction: predictionsById[match['id'].toString()]),
    ];
  }

  Future<MatchPredictionItem?> fetchMatchPrediction(String matchId) async {
    final match = await _client
        .from('matches')
        .select(_matchSelect)
        .eq('id', matchId)
        .maybeSingle();
    if (match == null) return null;

    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utilisateur non authentifié.');
    final prediction = await _client
        .from('match_predictions')
        .select(_predictionSelect)
        .eq('profile_id', userId)
        .eq('match_id', matchId)
        .maybeSingle();

    return _buildItem(
      Map<String, dynamic>.from(match),
      prediction:
          prediction == null ? null : Map<String, dynamic>.from(prediction),
    );
  }

  MatchPredictionItem _buildItem(
    Map<String, dynamic> matchMap, {
    required Map<String, dynamic>? prediction,
  }) {
    final matchId = matchMap['id'].toString();
    final serverKickoff = DateTime.tryParse(
      '${matchMap['kickoff_at'] ?? ''}',
    )?.toLocal();
    final date = matchMap['match_date']?.toString() ?? '';
    final time = matchMap['match_time']?.toString() ?? '00:00:00';
    final kickoffAt =
        serverKickoff ?? DateTime.tryParse('${date}T$time') ?? DateTime(1970);
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
      isHome: matchMap['location']?.toString() != 'exterieur',
      scoreGrinta:
          int.tryParse('${prediction?['predicted_score_as_grinta'] ?? 0}') ?? 0,
      scoreOpponent:
          int.tryParse('${prediction?['predicted_score_adverse'] ?? 0}') ?? 0,
      isFilled: prediction?['is_filled'] == true,
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
      )?.toLocal(),
    );
  }

  Future<void> savePrediction({
    required String matchId,
    required int scoreGrinta,
    required int scoreOpponent,
  }) async {
    if (_client.auth.currentUser == null) {
      throw StateError('Utilisateur non authentifié.');
    }
    if (scoreGrinta < 0 ||
        scoreGrinta > 99 ||
        scoreOpponent < 0 ||
        scoreOpponent > 99) {
      throw ArgumentError('Les scores doivent être compris entre 0 et 99.');
    }

    final result = await _client.rpc(
      'save_match_prediction',
      params: {
        'p_match_id': matchId,
        'p_score_as_grinta': scoreGrinta,
        'p_score_adverse': scoreOpponent,
      },
    );
    if (result != true) {
      throw StateError('Le pronostic n’a pas pu être enregistré.');
    }
  }
}

final predictionsRepositoryProvider = Provider<PredictionsRepository>((ref) {
  return PredictionsRepository(ref.watch(supabaseClientProvider));
});
