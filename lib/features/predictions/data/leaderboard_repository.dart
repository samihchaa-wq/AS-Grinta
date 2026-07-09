import 'dart:math' as math;

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.profileId,
    required this.name,
    required this.matchPoints,
    required this.seasonPoints,
  });

  final String profileId;
  final String name;
  final double matchPoints;
  final double seasonPoints;

  double get totalPoints => matchPoints + seasonPoints;
}

class LeaderboardRepository {
  LeaderboardRepository(this._client);

  final SupabaseClient _client;

  Future<List<LeaderboardEntry>> fetchCurrentLeaderboard() async {
    final profilesRaw = await _client
        .from('profiles')
        .select('id, first_name, last_name, status')
        .eq('status', 'active');
    final names = <String, String>{};
    for (final row in profilesRaw as List) {
      final map = Map<String, dynamic>.from(row);
      final id = map['id'].toString();
      final name = '${map['first_name'] ?? ''} ${map['last_name'] ?? ''}'.trim();
      names[id] = name.isEmpty ? 'Compte sans nom' : name;
    }

    final matchPoints = await _computeMatchPoints();
    final seasonPoints = await _computeSeasonPoints();
    final allIds = <String>{...names.keys, ...matchPoints.keys, ...seasonPoints.keys};
    final entries = allIds
        .map(
          (id) => LeaderboardEntry(
            profileId: id,
            name: names[id] ?? 'Compte archivé',
            matchPoints: matchPoints[id] ?? 0,
            seasonPoints: seasonPoints[id] ?? 0,
          ),
        )
        .toList();
    entries.sort((a, b) {
      final total = b.totalPoints.compareTo(a.totalPoints);
      if (total != 0) return total;
      final match = b.matchPoints.compareTo(a.matchPoints);
      if (match != 0) return match;
      return a.name.compareTo(b.name);
    });
    return entries;
  }

  Future<Map<String, double>> _computeMatchPoints() async {
    final rows = await _client.from('match_predictions').select('''
      profile_id,
      predicted_score_as_grinta,
      predicted_score_adverse,
      is_filled,
      matches!inner(
        score_as_grinta,
        score_adverse,
        status,
        match_odds(
          odds_victoire_as_grinta,
          odds_nul,
          odds_victoire_adverse
        )
      )
    ''').eq('is_filled', true);

    final totals = <String, double>{};
    for (final row in rows as List) {
      final map = Map<String, dynamic>.from(row);
      final match = Map<String, dynamic>.from(map['matches'] as Map);
      if (match['status'] != 'termine' && match['status'] != 'archive') continue;
      final actualFor = int.tryParse('${match['score_as_grinta']}');
      final actualAgainst = int.tryParse('${match['score_adverse']}');
      if (actualFor == null || actualAgainst == null) continue;
      final predictedFor = int.tryParse('${map['predicted_score_as_grinta']}') ?? 0;
      final predictedAgainst = int.tryParse('${map['predicted_score_adverse']}') ?? 0;
      final actualResult = _result(actualFor, actualAgainst);
      if (_result(predictedFor, predictedAgainst) != actualResult) continue;

      final oddsRaw = match['match_odds'];
      final odds = oddsRaw is List && oddsRaw.isNotEmpty
          ? Map<String, dynamic>.from(oddsRaw.first as Map)
          : oddsRaw is Map
              ? Map<String, dynamic>.from(oddsRaw)
              : const <String, dynamic>{};
      final odd = switch (actualResult) {
        1 => (odds['odds_victoire_as_grinta'] as num?)?.toDouble(),
        0 => (odds['odds_nul'] as num?)?.toDouble(),
        _ => (odds['odds_victoire_adverse'] as num?)?.toDouble(),
      };
      if (odd == null) continue;
      final exact = predictedFor == actualFor && predictedAgainst == actualAgainst;
      final profileId = map['profile_id'].toString();
      totals[profileId] = (totals[profileId] ?? 0) + odd * (exact ? 15 : 10);
    }
    return totals;
  }

  Future<Map<String, double>> _computeSeasonPoints() async {
    final season = await _client
        .from('seasons')
        .select('id, status')
        .eq('status', 'open')
        .maybeSingle();
    if (season == null) return const {};
    final seasonId = season['id'].toString();

    final matchesRaw = await _client
        .from('matches')
        .select('id, score_adverse, status')
        .eq('season_id', seasonId)
        .inFilter('status', ['termine', 'archive']);
    final completedMatches = <String, Map<String, dynamic>>{};
    for (final row in matchesRaw as List) {
      final map = Map<String, dynamic>.from(row);
      completedMatches[map['id'].toString()] = map;
    }

    final participantsRaw = await _client
        .from('match_participants')
        .select('match_id, profile_id')
        .inFilter('match_id', completedMatches.keys.toList());
    final matchesPlayed = <String, int>{};
    final participantPairs = <String>{};
    for (final row in participantsRaw as List) {
      final map = Map<String, dynamic>.from(row);
      final matchId = map['match_id'].toString();
      final playerId = map['profile_id'].toString();
      participantPairs.add('$matchId:$playerId');
      matchesPlayed[playerId] = (matchesPlayed[playerId] ?? 0) + 1;
    }

    final goalsRaw = await _client
        .from('goals')
        .select('match_id, team, scorer_profile_id, assist_profile_id')
        .inFilter('match_id', completedMatches.keys.toList());
    final goals = <String, int>{};
    final assists = <String, int>{};
    for (final row in goalsRaw as List) {
      final map = Map<String, dynamic>.from(row);
      if (map['team'] != 'as_grinta') continue;
      final scorer = map['scorer_profile_id']?.toString();
      final assister = map['assist_profile_id']?.toString();
      if (scorer != null) goals[scorer] = (goals[scorer] ?? 0) + 1;
      if (assister != null) assists[assister] = (assists[assister] ?? 0) + 1;
    }

    final motmRaw = await _client
        .from('match_motm')
        .select('match_id, profile_id')
        .inFilter('match_id', completedMatches.keys.toList());
    final motm = <String, int>{};
    for (final row in motmRaw as List) {
      final playerId = Map<String, dynamic>.from(row)['profile_id'].toString();
      motm[playerId] = (motm[playerId] ?? 0) + 1;
    }

    final cleanSheets = <String, int>{};
    for (final entry in completedMatches.entries) {
      final conceded = int.tryParse('${entry.value['score_adverse']}');
      if (conceded != 0) continue;
      for (final pair in participantPairs.where((pair) => pair.startsWith('${entry.key}:'))) {
        final playerId = pair.substring(entry.key.length + 1);
        cleanSheets[playerId] = (cleanSheets[playerId] ?? 0) + 1;
      }
    }

    final predictionsRaw = await _client
        .from('season_predictions')
        .select('predictor_profile_id, player_profile_id, category, predicted_value_20, is_filled')
        .eq('season_id', seasonId)
        .eq('is_filled', true);
    final totals = <String, double>{};
    for (final row in predictionsRaw as List) {
      final map = Map<String, dynamic>.from(row);
      final playerId = map['player_profile_id'].toString();
      final played = matchesPlayed[playerId] ?? 0;
      if (played == 0) continue;
      final predicted20 = int.tryParse('${map['predicted_value_20']}') ?? 0;
      final adjustedTarget = predicted20 * played / 20.0;
      final actual = switch (map['category']) {
        'buts' => goals[playerId] ?? 0,
        'passes' => assists[playerId] ?? 0,
        'hommes_du_match' => motm[playerId] ?? 0,
        'clean_sheets' => cleanSheets[playerId] ?? 0,
        _ => 0,
      };
      final precision = math.max(
        0.0,
        1 - (actual - adjustedTarget).abs() / math.max(adjustedTarget, 1),
      );
      final points = (precision * 20).roundToDouble();
      final predictorId = map['predictor_profile_id'].toString();
      totals[predictorId] = (totals[predictorId] ?? 0) + points;
    }
    return totals;
  }

  int _result(int grinta, int opponent) {
    if (grinta > opponent) return 1;
    if (grinta == opponent) return 0;
    return -1;
  }
}

final leaderboardRepositoryProvider = Provider<LeaderboardRepository>((ref) {
  return LeaderboardRepository(ref.watch(supabaseClientProvider));
});

final leaderboardProvider = FutureProvider<List<LeaderboardEntry>>((ref) {
  return ref.watch(leaderboardRepositoryProvider).fetchCurrentLeaderboard();
});
