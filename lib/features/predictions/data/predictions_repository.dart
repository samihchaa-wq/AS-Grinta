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
    required this.oddsWin,
    required this.oddsDraw,
    required this.oddsLoss,
    required this.actualScoreGrinta,
    required this.actualScoreOpponent,
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
  final int? actualScoreGrinta;
  final int? actualScoreOpponent;

  DateTime get opensAt => DateTime.fromMillisecondsSinceEpoch(0);
  DateTime get closesAt => kickoffAt.subtract(const Duration(minutes: 5));
  bool get isBeforeWindow => false;
  bool get isClosed => status != 'a_venir' || !DateTime.now().isBefore(closesAt);
  bool get canEdit => !isClosed;
  bool get hasResult => actualScoreGrinta != null && actualScoreOpponent != null;

  double? get earnedPoints {
    if (!isFilled || !hasResult) return hasResult ? 0 : null;
    final actualResult = _result(actualScoreGrinta!, actualScoreOpponent!);
    final odds = switch (actualResult) { 1 => oddsWin, 0 => oddsDraw, _ => oddsLoss };
    return PredictionScoring.points(
      predictedHome: scoreGrinta,
      predictedAway: scoreOpponent,
      actualHome: actualScoreGrinta!,
      actualAway: actualScoreOpponent!,
      baseOdds: odds,
    );
  }

  static int _result(int grinta, int opponent) {
    if (grinta > opponent) return 1;
    if (grinta == opponent) return 0;
    return -1;
  }

  MatchPredictionItem copyWith({int? scoreGrinta, int? scoreOpponent, bool? isFilled}) {
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
      actualScoreGrinta: actualScoreGrinta,
      actualScoreOpponent: actualScoreOpponent,
    );
  }
}

class PredictionsRepository {
  PredictionsRepository(this._client);
  final SupabaseClient _client;

  Future<List<MatchPredictionItem>> fetchMyMatchPredictions() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utilisateur non authentifié.');
    final matches = await _client.from('matches').select('''
      id,match_date,match_time,status,score_as_grinta,score_adverse,
      opponents(name),match_odds(odds_victoire_as_grinta,odds_nul,odds_victoire_adverse)
    ''').eq('status','a_venir').order('match_date').order('match_time').limit(1);
    if ((matches as List).isEmpty) return const [];
    final map = Map<String,dynamic>.from(matches.first as Map);
    final matchId = map['id'].toString();
    final prediction = await _client.from('match_predictions')
      .select('match_id,predicted_score_as_grinta,predicted_score_adverse,is_filled')
      .eq('profile_id',userId).eq('match_id',matchId).maybeSingle();
    final kickoff = DateTime.tryParse('${map['match_date']}T${map['match_time'] ?? '00:00:00'}') ?? DateTime(1970);
    final opponent = map['opponents'] is Map ? Map<String,dynamic>.from(map['opponents']) : <String,dynamic>{};
    final oddsRaw = map['match_odds'];
    final odds = oddsRaw is List && oddsRaw.isNotEmpty ? Map<String,dynamic>.from(oddsRaw.first) : oddsRaw is Map ? Map<String,dynamic>.from(oddsRaw) : <String,dynamic>{};
    return [MatchPredictionItem(
      matchId: matchId,
      opponentName: opponent['name']?.toString() ?? 'Adversaire',
      kickoffAt: kickoff,
      status: map['status']?.toString() ?? 'a_venir',
      scoreGrinta: int.tryParse('${prediction?['predicted_score_as_grinta'] ?? 0}') ?? 0,
      scoreOpponent: int.tryParse('${prediction?['predicted_score_adverse'] ?? 0}') ?? 0,
      isFilled: prediction?['is_filled'] == true,
      oddsWin: (odds['odds_victoire_as_grinta'] as num?)?.toDouble(),
      oddsDraw: (odds['odds_nul'] as num?)?.toDouble(),
      oddsLoss: (odds['odds_victoire_adverse'] as num?)?.toDouble(),
      actualScoreGrinta: map['score_as_grinta'] == null ? null : int.tryParse('${map['score_as_grinta']}'),
      actualScoreOpponent: map['score_adverse'] == null ? null : int.tryParse('${map['score_adverse']}'),
    )];
  }

  Future<void> savePrediction({required String matchId,required int scoreGrinta,required int scoreOpponent}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utilisateur non authentifié.');
    if (scoreGrinta < 0 || scoreGrinta > 99 || scoreOpponent < 0 || scoreOpponent > 99) {
      throw ArgumentError('Les scores doivent être compris entre 0 et 99.');
    }
    final match = await _client.from('matches').select('match_date,match_time,status').eq('id',matchId).single();
    final kickoff = DateTime.tryParse('${match['match_date']}T${match['match_time'] ?? '00:00:00'}');
    if (kickoff == null || match['status'] != 'a_venir' || !DateTime.now().isBefore(kickoff.subtract(const Duration(minutes: 5)))) {
      throw StateError('Ce pronostic est fermé.');
    }
    await _client.from('match_predictions').upsert({
      'match_id':matchId,'profile_id':userId,
      'predicted_score_as_grinta':scoreGrinta,'predicted_score_adverse':scoreOpponent,
      'is_filled':true,'updated_at':DateTime.now().toUtc().toIso8601String(),
    },onConflict:'match_id,profile_id');
  }
}

final predictionsRepositoryProvider = Provider<PredictionsRepository>((ref) => PredictionsRepository(ref.watch(supabaseClientProvider)));
