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

class MatchStatLine {
  const MatchStatLine({
    required this.name,
    required this.goals,
    required this.cleanSheet,
  });

  final String name;
  final int goals;
  final bool cleanSheet;
}

class MatchPredictionResult {
  const MatchPredictionResult({
    required this.profileId,
    required this.name,
    required this.scoreGrinta,
    required this.scoreOpponent,
    required this.points,
    required this.usedX2,
  });

  final String profileId;
  final String name;
  final int scoreGrinta;
  final int scoreOpponent;

  /// Points déjà convertis en base 100 pour l'affichage.
  /// Exemple : 3,10 points réels deviennent 310.
  final double points;
  final bool usedX2;
}

class MatchDetailsData {
  const MatchDetailsData({
    required this.matchId,
    required this.opponentId,
    required this.opponentName,
    required this.kickoffAt,
    required this.status,
    required this.location,
    required this.scoreGrinta,
    required this.scoreOpponent,
    required this.oddsWin,
    required this.oddsDraw,
    required this.oddsLoss,
    required this.predictionParticipantCount,
    required this.headToHead,
    required this.playerStats,
    required this.predictions,
  });

  final String matchId;
  final String opponentId;
  final String opponentName;
  final DateTime kickoffAt;
  final String status;
  final String location;
  final int? scoreGrinta;
  final int? scoreOpponent;
  final double? oddsWin;
  final double? oddsDraw;
  final double? oddsLoss;
  final int predictionParticipantCount;
  final List<HeadToHeadMatch> headToHead;
  final List<MatchStatLine> playerStats;
  final List<MatchPredictionResult> predictions;

  bool get isValidated => status == 'termine' || status == 'archive';
}

class MatchDetailsRepository {
  MatchDetailsRepository(this._client);

  final SupabaseClient _client;

  Future<MatchDetailsData> fetch(String matchId) async {
    final match = await _client.from('matches').select('''
      id, opponent_id, match_date, match_time, kickoff_at, status, location,
      score_as_grinta, score_adverse, opponents(name),
      match_odds(odds_victoire_as_grinta, odds_nul, odds_victoire_adverse)
    ''').eq('id', matchId).maybeSingle();
    if (match == null) {
      throw StateError('Ce match est introuvable ou a été supprimé.');
    }
    final opponentId = match['opponent_id'].toString();
    final opponent = Map<String, dynamic>.from(match['opponents'] as Map);
    final serverKickoff = DateTime.tryParse(
      '${match['kickoff_at'] ?? ''}',
    )?.toLocal();
    final kickoffAt = serverKickoff ??
        DateTime.tryParse('${match['match_date']}T${match['match_time']}') ??
        DateTime(1970);
    final oddsRaw = match['match_odds'];
    final odds = oddsRaw is List && oddsRaw.isNotEmpty
        ? Map<String, dynamic>.from(oddsRaw.first as Map)
        : oddsRaw is Map
            ? Map<String, dynamic>.from(oddsRaw)
            : const <String, dynamic>{};
    final status = match['status']?.toString() ?? 'a_venir';
    final isValidated = status == 'termine' || status == 'archive';

    final countResult = await _client.rpc(
      'match_prediction_participant_count',
      params: {'p_match_id': matchId},
    );

    final historyRaw = await _client
        .from('matches')
        .select('match_date, location, score_as_grinta, score_adverse')
        .eq('opponent_id', opponentId)
        .neq('id', matchId)
        .inFilter('status', const ['termine', 'archive'])
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

    var playerStats = const <MatchStatLine>[];
    var predictions = const <MatchPredictionResult>[];

    if (isValidated) {
      final statRows = await _client.from('match_player_stats').select('''
        goals,clean_sheet,
        season_players(first_name,last_name)
      ''').eq('match_id', matchId);
      playerStats = (statRows as List).map((row) {
        final map = Map<String, dynamic>.from(row);
        final player = map['season_players'] is Map
            ? Map<String, dynamic>.from(map['season_players'] as Map)
            : const <String, dynamic>{};
        return MatchStatLine(
          name: _displayName(player),
          goals: (map['goals'] as num?)?.toInt() ?? 0,
          cleanSheet: map['clean_sheet'] == true,
        );
      }).toList()
        ..sort((a, b) => b.goals.compareTo(a.goals));

      final pointRows = await _client
          .from('v_match_prediction_points')
          .select('profile_id,points')
          .eq('match_id', matchId);
      final pointsByProfile = <String, double>{};
      for (final row in pointRows as List) {
        final map = Map<String, dynamic>.from(row);
        final decimalPoints = (map['points'] as num?)?.toDouble() ?? 0;
        pointsByProfile[map['profile_id'].toString()] = decimalPoints * 100;
      }

      final predictionRows = await _client.from('match_predictions').select('''
        profile_id,predicted_score_as_grinta,predicted_score_adverse,use_x2,
        profiles(first_name,surnom)
      ''').eq('match_id', matchId).eq('is_filled', true);
      predictions = (predictionRows as List).map((row) {
        final map = Map<String, dynamic>.from(row);
        final profileId = map['profile_id'].toString();
        final profile = map['profiles'] is Map
            ? Map<String, dynamic>.from(map['profiles'] as Map)
            : const <String, dynamic>{};
        return MatchPredictionResult(
          profileId: profileId,
          name: _displayName(profile),
          scoreGrinta: (map['predicted_score_as_grinta'] as num?)?.toInt() ?? 0,
          scoreOpponent: (map['predicted_score_adverse'] as num?)?.toInt() ?? 0,
          points: pointsByProfile[profileId] ?? 0,
          usedX2: map['use_x2'] == true,
        );
      }).toList()
        ..sort((a, b) => b.points.compareTo(a.points));
    }

    return MatchDetailsData(
      matchId: matchId,
      opponentId: opponentId,
      opponentName: opponent['name']?.toString() ?? 'Adversaire',
      kickoffAt: kickoffAt,
      status: status,
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
      playerStats: playerStats,
      predictions: predictions,
    );
  }

  static String _displayName(Map<String, dynamic> profile) {
    final firstName = (profile['first_name'] ?? '').toString().trim();
    return firstName.isEmpty ? 'Joueur' : firstName;
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

final matchDetailsProvider = FutureProvider.family<MatchDetailsData, String>((
  ref,
  matchId,
) {
  return ref.watch(matchDetailsRepositoryProvider).fetch(matchId);
});
