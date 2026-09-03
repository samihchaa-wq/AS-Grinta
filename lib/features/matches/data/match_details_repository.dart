import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HeadToHeadMatch {
  const HeadToHeadMatch({
    required this.date,
    required this.scoreGrinta,
    required this.scoreOpponent,
    this.location = '',
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
    required this.assists,
    required this.cleanSheet,
  });

  final String name;
  final int goals;

  /// Passes décisives du joueur sur ce match.
  final int assists;
  final bool cleanSheet;
}

class MatchStartingPlayer {
  const MatchStartingPlayer({
    required this.seasonPlayerId,
    required this.name,
    required this.goals,
    required this.isManOfTheMatch,
    required this.sortOrder,
    required this.isStarter,
    required this.x,
    required this.y,
  });

  final String? seasonPlayerId;
  final String name;
  final int goals;
  final bool isManOfTheMatch;
  final int sortOrder;
  final bool isStarter;
  final double? x;
  final double? y;
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
  final double points;
  final bool usedX2;
}

class MatchDetailsData {
  const MatchDetailsData({
    required this.matchId,
    required this.opponentId,
    required this.opponentName,
    required this.isInternal,
    required this.kickoffAt,
    required this.status,
    required this.resultValidatedAt,
    required this.location,
    required this.address,
    required this.matchType,
    required this.championshipRound,
    required this.scoreGrinta,
    required this.scoreOpponent,
    required this.oddsWin,
    required this.oddsDraw,
    required this.oddsLoss,
    required this.predictionParticipantCount,
    required this.headToHead,
    required this.playerStats,
    required this.startingLineup,
    required this.predictions,
  });

  final String matchId;

  /// Absent pour un match entre nous, qui n'a pas d'adversaire réel.
  final String? opponentId;
  final String opponentName;

  /// Vrai pour un match entre nous (pas d'adversaire, pas de cotes, pas de
  /// pronostics ni d'historique face-à-face).
  final bool isInternal;
  final DateTime kickoffAt;
  final String status;

  /// Instant de la première validation du compte rendu. Le serveur empêche les
  /// corrections ultérieures de déplacer cette ancre.
  final DateTime? resultValidatedAt;
  final String location;
  final String? address;
  final String matchType;
  final int? championshipRound;
  final int? scoreGrinta;
  final int? scoreOpponent;
  final double? oddsWin;
  final double? oddsDraw;
  final double? oddsLoss;
  final int predictionParticipantCount;
  final List<HeadToHeadMatch> headToHead;
  final List<MatchStatLine> playerStats;
  final List<MatchStartingPlayer> startingLineup;
  final List<MatchPredictionResult> predictions;

  bool get isValidated => status == 'termine' || status == 'archive';
  bool get isFriendly => matchType == 'amical';

  String get matchTypeLabel {
    if (isInternal) return 'Match entre nous';
    if (isFriendly) return 'Match amical';
    final round = championshipRound;
    return round == null ? 'Championnat' : 'Championnat · J$round';
  }
}

class MatchDetailsRepository {
  MatchDetailsRepository(this._client);

  final SupabaseClient _client;

  Future<MatchDetailsData> fetch(String matchId) async {
    final match = await _client.from('matches').select('''
      id, opponent_id, match_date, match_time, kickoff_at, status, location,
      address, match_type, championship_round, score_as_grinta, score_adverse,
      result_validated_at, opponents(name, address),
      match_odds(odds_victoire_as_grinta, odds_nul, odds_victoire_adverse)
    ''').eq('id', matchId).maybeSingle();
    if (match == null) {
      throw StateError('Ce match est introuvable ou a été supprimé.');
    }
    // Un match entre nous n'a pas d'adversaire réel : ni opponent_id, ni
    // ligne opponents jointe.
    final matchType = match['match_type']?.toString() ?? 'championnat';
    final isInternal = matchType == 'entre_nous';
    final opponentId = match['opponent_id']?.toString();
    final opponent = match['opponents'] is Map
        ? Map<String, dynamic>.from(match['opponents'] as Map)
        : const <String, dynamic>{};
    final serverKickoff =
        DateTime.tryParse('${match['kickoff_at'] ?? ''}')?.toLocal();
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

    // Pas d'historique face-à-face pour un match entre nous : il n'y a pas
    // d'adversaire réel à comparer.
    // La table `matches` ne contient que les rencontres saisies dans
    // l'application : interrogée seule, elle annonçait « Aucune confrontation
    // précédente » face à un adversaire déjà rencontré des dizaines de fois.
    // La RPC fait l'union avec `historical_match_scores`, comme l'onglet Info.
    final List historyRaw = isInternal || opponentId == null
        ? const []
        : await _client.rpc(
            'get_last_opponent_encounters',
            params: {'p_match_id': matchId},
          ) as List;
    final history = historyRaw
        .map((row) => Map<String, dynamic>.from(row as Map))
        .map(
          (row) => HeadToHeadMatch(
            date:
                DateTime.tryParse('${row['encounter_date']}') ?? DateTime(1970),
            scoreGrinta: (row['grinta_score'] as num?)?.toInt(),
            scoreOpponent: (row['opponent_score'] as num?)?.toInt(),
          ),
        )
        .toList();

    var playerStats = const <MatchStatLine>[];
    var startingLineup = const <MatchStartingPlayer>[];
    var predictions = const <MatchPredictionResult>[];

    if (isValidated) {
      final statRows = await _client.from('match_player_stats').select('''
        season_player_id,goals,assists,clean_sheet,
        season_players(first_name,last_name,profiles(surnom))
      ''').eq('match_id', matchId);
      final statsByPlayerId = <String, MatchStatLine>{};
      playerStats = (statRows as List).map((row) {
        final map = Map<String, dynamic>.from(row);
        final player = map['season_players'] is Map
            ? Map<String, dynamic>.from(map['season_players'] as Map)
            : const <String, dynamic>{};
        final playerProfile = player['profiles'] is Map
            ? Map<String, dynamic>.from(player['profiles'] as Map)
            : const <String, dynamic>{};
        final stat = MatchStatLine(
          name: _resolveName(
            playerProfile['surnom'],
            player['first_name'],
            player['last_name'],
          ),
          goals: (map['goals'] as num?)?.toInt() ?? 0,
          assists: (map['assists'] as num?)?.toInt() ?? 0,
          cleanSheet: map['clean_sheet'] == true,
        );
        final seasonPlayerId = map['season_player_id']?.toString();
        if (seasonPlayerId != null && seasonPlayerId.isNotEmpty) {
          statsByPlayerId[seasonPlayerId] = stat;
        }
        return stat;
      }).toList()
        ..sort((a, b) => b.goals.compareTo(a.goals));

      final publication = await _client
          .from('match_composition_publications')
          .select('snapshot')
          .eq('match_id', matchId)
          .order('version', ascending: false)
          .order('published_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final manOfMatchRows = await _client
          .from('match_man_of_match')
          .select('season_player_id')
          .eq('match_id', matchId);
      final manOfMatchIds = {
        for (final raw in manOfMatchRows as List)
          if ((raw as Map)['season_player_id'] != null)
            raw['season_player_id'].toString(),
      };
      final snapshot = publication?['snapshot'];
      if (snapshot is Map && snapshot['entries'] is List) {
        startingLineup = (snapshot['entries'] as List)
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .where(
              (entry) =>
                  entry['zone']?.toString() == 'field' ||
                  entry['zone']?.toString() == 'bench',
            )
            .map((entry) {
          final seasonPlayerId = entry['season_player_id']?.toString();
          final stat =
              seasonPlayerId == null ? null : statsByPlayerId[seasonPlayerId];
          final isStarter = entry['zone']?.toString() == 'field';
          return MatchStartingPlayer(
            seasonPlayerId: seasonPlayerId,
            name: (entry['display_name'] ?? 'Joueur').toString().trim(),
            goals: stat?.goals ?? 0,
            isManOfTheMatch: seasonPlayerId != null &&
                manOfMatchIds.contains(seasonPlayerId),
            sortOrder: (entry['sort_order'] as num?)?.toInt() ?? 0,
            isStarter: isStarter,
            x: isStarter ? (entry['x'] as num?)?.toDouble() : null,
            y: isStarter ? (entry['y'] as num?)?.toDouble() : null,
          );
        }).toList()
          ..sort((a, b) {
            if (a.isStarter != b.isStarter) return a.isStarter ? -1 : 1;
            return a.sortOrder.compareTo(b.sortOrder);
          });
      }

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
        profile_id,predicted_score_as_grinta,predicted_score_adverse,
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
          name: _resolveName(profile['surnom'], profile['first_name']),
          scoreGrinta: (map['predicted_score_as_grinta'] as num?)?.toInt() ?? 0,
          scoreOpponent: (map['predicted_score_adverse'] as num?)?.toInt() ?? 0,
          points: pointsByProfile[profileId] ?? 0,
          usedX2: false,
        );
      }).toList()
        ..sort((a, b) => b.points.compareTo(a.points));
    }

    final directAddress = _clean(match['address']);
    final opponentAddress = _clean(opponent['address']);
    final location = (match['location'] ?? 'domicile').toString();

    return MatchDetailsData(
      matchId: matchId,
      opponentId: opponentId,
      opponentName: isInternal
          ? 'Match entre nous'
          : opponent['name']?.toString() ?? 'Adversaire',
      isInternal: isInternal,
      kickoffAt: kickoffAt,
      status: status,
      resultValidatedAt: DateTime.tryParse(
        '${match['result_validated_at'] ?? ''}',
      )?.toLocal(),
      location: location,
      address:
          directAddress ?? (location == 'exterieur' ? opponentAddress : null),
      matchType: matchType,
      championshipRound: (match['championship_round'] as num?)?.toInt(),
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
      startingLineup: startingLineup,
      predictions: predictions,
    );
  }

  /// Nom court unifié : surnom s'il est renseigné, sinon prénom (repli sur
  /// prénom + nom). Même règle que partout ailleurs dans l'app.
  static String _resolveName(
    Object? surnom,
    Object? firstName, [
    Object? lastName,
  ]) {
    final nick = (surnom ?? '').toString().trim();
    if (nick.isNotEmpty) return nick;
    final first = (firstName ?? '').toString().trim();
    if (first.isNotEmpty) return first;
    final full = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    return full.isEmpty ? 'Joueur' : full;
  }

  static String? _clean(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
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
