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
    this.isHome = true,
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
    this.isFirstOpenMatch = true,
  });

  final String matchId;
  final String opponentName;
  final DateTime kickoffAt;
  final String status;

  /// Vrai si AS Grinta reçoit (domicile). Sert à afficher l'équipe qui reçoit
  /// à gauche, comme sur le reste de l'app.
  final bool isHome;
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

  /// Le serveur n’autorise qu’un seul match à la fois : le premier match dont
  /// la fenêtre temporelle est encore ouverte.
  final bool isFirstOpenMatch;

  DateTime get closesAt => kickoffAt.subtract(const Duration(minutes: 5));

  bool isTimeClosedAt(DateTime now) =>
      status != 'a_venir' ||
      !now.isBefore(closesAt) ||
      (predictionsClosedAt != null && !now.isBefore(predictionsClosedAt!));

  bool isClosedAt(DateTime now) => !isFirstOpenMatch || isTimeClosedAt(now);

  bool isWaitingForPreviousMatchAt(DateTime now) =>
      !isFirstOpenMatch && !isTimeClosedAt(now);

  bool canEditAt(DateTime now) => !isClosedAt(now);
  bool get isClosed => isClosedAt(DateTime.now());
  bool get isWaitingForPreviousMatch =>
      isWaitingForPreviousMatchAt(DateTime.now());
  bool get canEdit => canEditAt(DateTime.now());
  bool get hasResult =>
      actualScoreGrinta != null && actualScoreOpponent != null;

  MatchPredictionItem updated({
    int? scoreGrinta,
    int? scoreOpponent,
    bool? isFilled,
    bool? useX2,
  }) {
    return MatchPredictionItem(
      matchId: matchId,
      opponentName: opponentName,
      kickoffAt: kickoffAt,
      status: status,
      isHome: isHome,
      scoreGrinta: scoreGrinta ?? this.scoreGrinta,
      scoreOpponent: scoreOpponent ?? this.scoreOpponent,
      isFilled: isFilled ?? this.isFilled,
      useX2: useX2 ?? this.useX2,
      x2Available: x2Available,
      oddsWin: oddsWin,
      oddsDraw: oddsDraw,
      oddsLoss: oddsLoss,
      actualScoreGrinta: actualScoreGrinta,
      actualScoreOpponent: actualScoreOpponent,
      predictionsClosedAt: predictionsClosedAt,
      isFirstOpenMatch: isFirstOpenMatch,
    );
  }

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

  Future<List<MatchPredictionItem>> fetchMyMatchPredictions() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utilisateur non authentifié.');
    final response = await _client
        .from('matches')
        .select(_matchSelect)
        .eq('status', 'a_venir')
        .order('kickoff_at', ascending: true);
    final matches = (response as List)
        .map((match) => Map<String, dynamic>.from(match as Map))
        .toList();
    final firstOpenMatchId = _firstOpenMatchId(matches, DateTime.now());
    final matchIds = [for (final match in matches) match['id'].toString()];

    // Portefeuille ×2 : identique pour tous les matchs, lu une seule fois.
    final x2Available = await _fetchX2Available(userId);

    // Tous les pronos de l'utilisateur en un seul appel (au lieu d'un par match).
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
        _buildItem(
          match,
          prediction: predictionsById[match['id'].toString()],
          x2Available: x2Available,
          isFirstOpenMatch: match['id']?.toString() == firstOpenMatchId,
        ),
    ];
  }

  Future<MatchPredictionItem?> fetchMatchPrediction(String matchId) async {
    final match = await _client
        .from('matches')
        .select(_matchSelect)
        .eq('id', matchId)
        .maybeSingle();
    if (match == null) return null;

    final openResponse = await _client
        .from('matches')
        .select('id, kickoff_at, status, predictions_closed_at')
        .eq('status', 'a_venir')
        .order('kickoff_at', ascending: true);
    final openMatches = (openResponse as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    final firstOpenMatchId = _firstOpenMatchId(openMatches, DateTime.now());

    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utilisateur non authentifié.');
    final prediction = await _client
        .from('match_predictions')
        .select(_predictionSelect)
        .eq('profile_id', userId)
        .eq('match_id', matchId)
        .maybeSingle();
    final x2Available = await _fetchX2Available(userId);

    return _buildItem(
      Map<String, dynamic>.from(match),
      prediction: prediction == null
          ? null
          : Map<String, dynamic>.from(prediction),
      x2Available: x2Available,
      isFirstOpenMatch: matchId == firstOpenMatchId,
    );
  }

  Future<int> _fetchX2Available(String userId) async {
    final wallet = await _client
        .from('v_x2_wallet')
        .select('available_count')
        .eq('profile_id', userId)
        .maybeSingle();
    return (wallet?['available_count'] as num?)?.toInt() ?? 0;
  }

  String? _firstOpenMatchId(List<Map<String, dynamic>> matches, DateTime now) {
    for (final match in matches) {
      if (match['status']?.toString() != 'a_venir') continue;
      final kickoffAt = DateTime.tryParse(
        '${match['kickoff_at'] ?? ''}',
      )?.toLocal();
      if (kickoffAt == null ||
          !now.isBefore(kickoffAt.subtract(const Duration(minutes: 5)))) {
        continue;
      }
      final closedAt = DateTime.tryParse(
        '${match['predictions_closed_at'] ?? ''}',
      )?.toLocal();
      if (closedAt != null && !now.isBefore(closedAt)) continue;
      return match['id']?.toString();
    }
    return null;
  }

  static const _predictionSelect =
      'match_id, predicted_score_as_grinta, predicted_score_adverse, '
      'is_filled, use_x2';

  MatchPredictionItem _buildItem(
    Map<String, dynamic> matchMap, {
    required Map<String, dynamic>? prediction,
    required int x2Available,
    required bool isFirstOpenMatch,
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
      useX2: prediction?['use_x2'] == true,
      x2Available: x2Available,
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
      isFirstOpenMatch: isFirstOpenMatch,
    );
  }

  Future<void> savePrediction({
    required String matchId,
    required int scoreGrinta,
    required int scoreOpponent,
    required bool useX2,
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
        'p_use_x2': useX2,
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
