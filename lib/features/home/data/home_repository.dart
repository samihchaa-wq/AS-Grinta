import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RecentMeeting {
  const RecentMeeting({
    required this.date,
    required this.grintaScore,
    required this.opponentScore,
  });

  final DateTime date;
  final int grintaScore;
  final int opponentScore;

  bool get isWin => grintaScore > opponentScore;
  bool get isDraw => grintaScore == opponentScore;
}

class HomeDashboardData {
  const HomeDashboardData({
    required this.nextMatchId,
    required this.nextOpponent,
    required this.nextKickoffAt,
    required this.nextMatchStatus,
    required this.nextGrintaScore,
    required this.nextOpponentScore,
    required this.pendingPredictions,
    required this.predictionParticipantCount,
    required this.recentMeetings,
  });

  final String? nextMatchId;
  final String? nextOpponent;
  final DateTime? nextKickoffAt;

  /// Statut du match mis en avant : 'a_venir' (avant ou après le coup
  /// d'envoi) ou 'termine' (résultat validé mais pas encore archivé).
  final String nextMatchStatus;
  final int? nextGrintaScore;
  final int? nextOpponentScore;
  final int pendingPredictions;
  final int predictionParticipantCount;
  final List<RecentMeeting> recentMeetings;

  bool get isUpcoming => nextMatchStatus == 'a_venir';
  bool get isValidated => nextMatchStatus == 'termine';
  bool get isAwaitingResult =>
      isUpcoming &&
      nextKickoffAt != null &&
      DateTime.now().isAfter(nextKickoffAt!);
}

class HomeRepository {
  HomeRepository(this._client);

  final SupabaseClient _client;

  Future<HomeDashboardData> fetchDashboard() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utilisateur non authentifié.');

    // Un match reste à l'accueil tant que l'admin ne l'a pas archivé :
    // « À venir » avant le coup d'envoi, « En attente » ensuite, puis le
    // résultat une fois validé.
    final matches = await _client
        .from('matches')
        .select(
          'id, opponent_id, match_date, match_time, status, '
          'score_as_grinta, score_adverse, opponents(name)',
        )
        .inFilter('status', const ['a_venir', 'termine'])
        .order('match_date', ascending: true)
        .order('match_time', ascending: true);

    final predictions = await _client
        .from('match_predictions')
        .select('match_id, is_filled')
        .eq('profile_id', userId);
    final filledByMatch = <String, bool>{};
    for (final row in predictions as List) {
      final map = Map<String, dynamic>.from(row);
      filledByMatch[map['match_id'].toString()] = map['is_filled'] == true;
    }

    String? nextMatchId;
    String? nextOpponentId;
    String? nextOpponent;
    DateTime? nextKickoffAt;
    var nextMatchStatus = 'a_venir';
    int? nextGrintaScore;
    int? nextOpponentScore;
    var pendingPredictions = 0;
    var predictionParticipantCount = 0;
    final now = DateTime.now();

    Map<String, dynamic>? heroRow;
    for (final row in matches as List) {
      final map = Map<String, dynamic>.from(row);
      final id = map['id'].toString();
      final status = (map['status'] ?? 'a_venir').toString();
      final date = map['match_date']?.toString() ?? '';
      final time = map['match_time']?.toString() ?? '00:00:00';
      final kickoff = DateTime.tryParse('${date}T$time');

      // Match mis en avant : le premier « à venir » (même après le coup
      // d'envoi) ; sinon le dernier « terminé » non archivé. La liste est
      // triée par date croissante : les terminés se remplacent jusqu'à ce
      // qu'un « à venir » prenne la place, qu'il garde ensuite.
      if (heroRow == null || (heroRow['status'] ?? '') != 'a_venir') {
        heroRow = map;
      }

      if (status == 'a_venir' &&
          kickoff != null &&
          now.isBefore(kickoff.subtract(const Duration(minutes: 5))) &&
          filledByMatch[id] != true) {
        pendingPredictions++;
      }
    }

    if (heroRow != null) {
      final opponent = heroRow['opponents'] is Map
          ? Map<String, dynamic>.from(heroRow['opponents'] as Map)
          : const <String, dynamic>{};
      nextMatchId = heroRow['id'].toString();
      nextOpponentId = heroRow['opponent_id']?.toString();
      nextOpponent = opponent['name']?.toString() ?? 'Adversaire';
      nextMatchStatus = (heroRow['status'] ?? 'a_venir').toString();
      nextGrintaScore = (heroRow['score_as_grinta'] as num?)?.toInt();
      nextOpponentScore = (heroRow['score_adverse'] as num?)?.toInt();
      final date = heroRow['match_date']?.toString() ?? '';
      final time = heroRow['match_time']?.toString() ?? '00:00:00';
      nextKickoffAt = DateTime.tryParse('${date}T$time');
    }

    if (nextMatchId != null) {
      final count = await _client.rpc(
        'match_prediction_participant_count',
        params: {'p_match_id': nextMatchId},
      );
      predictionParticipantCount = (count as num?)?.toInt() ?? 0;
    }

    final recentMeetings = <RecentMeeting>[];
    if (nextOpponentId != null) {
      final history = await _client
          .from('matches')
          .select('match_date, score_as_grinta, score_adverse')
          .eq('opponent_id', nextOpponentId)
          .inFilter('status', const ['termine', 'archive'])
          .not('score_as_grinta', 'is', null)
          .not('score_adverse', 'is', null)
          .order('match_date', ascending: false)
          .limit(5);

      for (final row in history as List) {
        final map = Map<String, dynamic>.from(row);
        final date = DateTime.tryParse(map['match_date']?.toString() ?? '');
        final grinta = (map['score_as_grinta'] as num?)?.toInt();
        final opponent = (map['score_adverse'] as num?)?.toInt();
        if (date != null && grinta != null && opponent != null) {
          recentMeetings.add(
            RecentMeeting(
              date: date,
              grintaScore: grinta,
              opponentScore: opponent,
            ),
          );
        }
      }
    }

    return HomeDashboardData(
      nextMatchId: nextMatchId,
      nextOpponent: nextOpponent,
      nextKickoffAt: nextKickoffAt,
      nextMatchStatus: nextMatchStatus,
      nextGrintaScore: nextGrintaScore,
      nextOpponentScore: nextOpponentScore,
      pendingPredictions: pendingPredictions,
      predictionParticipantCount: predictionParticipantCount,
      recentMeetings: recentMeetings,
    );
  }
}

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  return HomeRepository(ref.watch(supabaseClientProvider));
});

final homeDashboardProvider = FutureProvider<HomeDashboardData>((ref) {
  return ref.watch(homeRepositoryProvider).fetchDashboard();
});
