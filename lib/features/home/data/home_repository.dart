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

/// Un match mis en avant sur l'accueil (prochain ou dernier joué).
class HomeMatch {
  const HomeMatch({
    required this.id,
    required this.opponentId,
    required this.opponent,
    required this.isHome,
    required this.kickoffAt,
    required this.status,
    required this.grintaScore,
    required this.opponentScore,
    required this.predictionsClosed,
    required this.oddsWin,
    required this.oddsDraw,
    required this.oddsLoss,
  });

  final String id;
  final String? opponentId;
  final String opponent;
  final bool isHome;
  final DateTime? kickoffAt;

  /// 'a_venir', 'termine' ou 'archive'.
  final String status;
  final int? grintaScore;
  final int? opponentScore;
  final bool predictionsClosed;
  final double? oddsWin;
  final double? oddsDraw;
  final double? oddsLoss;

  bool get isAwaitingResult =>
      status == 'a_venir' &&
      kickoffAt != null &&
      DateTime.now().isAfter(kickoffAt!);

  bool get hasOdds => oddsWin != null && oddsDraw != null && oddsLoss != null;
}

class HomeDashboardData {
  const HomeDashboardData({
    required this.nextMatch,
    required this.lastMatch,
    required this.pendingPredictions,
    required this.predictionParticipantCount,
    required this.recentMeetings,
  });

  /// Le prochain match à venir (avant ou après le coup d'envoi), ou null.
  final HomeMatch? nextMatch;

  /// Le dernier match joué (résultat validé), ou null.
  final HomeMatch? lastMatch;

  final int pendingPredictions;

  /// Nombre de participants ayant pronostiqué sur le prochain match.
  final int predictionParticipantCount;

  /// Les 5 dernières confrontations face à l'adversaire du prochain match.
  final List<RecentMeeting> recentMeetings;
}

class HomeRepository {
  HomeRepository(this._client);

  final SupabaseClient _client;

  HomeMatch _toMatch(Map<String, dynamic> map) {
    final opponent = map['opponents'] is Map
        ? Map<String, dynamic>.from(map['opponents'] as Map)
        : const <String, dynamic>{};
    final date = map['match_date']?.toString() ?? '';
    final time = map['match_time']?.toString() ?? '00:00:00';

    // match_odds peut arriver en Map (relation 1-1) ou en List.
    Map<String, dynamic>? odds;
    final rawOdds = map['match_odds'];
    if (rawOdds is Map) {
      odds = Map<String, dynamic>.from(rawOdds);
    } else if (rawOdds is List && rawOdds.isNotEmpty) {
      odds = Map<String, dynamic>.from(rawOdds.first as Map);
    }

    return HomeMatch(
      id: map['id'].toString(),
      opponentId: map['opponent_id']?.toString(),
      opponent: opponent['name']?.toString() ?? 'Adversaire',
      isHome: (map['location']?.toString() ?? 'domicile') == 'domicile',
      kickoffAt: DateTime.tryParse('${date}T$time'),
      status: (map['status'] ?? 'a_venir').toString(),
      grintaScore: (map['score_as_grinta'] as num?)?.toInt(),
      opponentScore: (map['score_adverse'] as num?)?.toInt(),
      predictionsClosed: map['predictions_closed_at'] != null,
      oddsWin: (odds?['odds_victoire_as_grinta'] as num?)?.toDouble(),
      oddsDraw: (odds?['odds_nul'] as num?)?.toDouble(),
      oddsLoss: (odds?['odds_victoire_adverse'] as num?)?.toDouble(),
    );
  }

  Future<HomeDashboardData> fetchDashboard() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utilisateur non authentifié.');

    final rows = await _client
        .from('matches')
        .select(
          'id, opponent_id, match_date, match_time, location, status, '
          'score_as_grinta, score_adverse, predictions_closed_at, '
          'opponents(name), '
          'match_odds(odds_victoire_as_grinta, odds_nul, odds_victoire_adverse)',
        )
        .inFilter('status', const ['a_venir', 'termine', 'archive'])
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

    HomeMatch? nextMatch;
    HomeMatch? lastMatch;
    var pendingPredictions = 0;
    final now = DateTime.now();

    for (final row in rows as List) {
      final map = Map<String, dynamic>.from(row);
      final match = _toMatch(map);

      // Prochain match : le premier « à venir » (liste triée par date
      // croissante). Dernier joué : le plus récent terminé/archivé.
      if (match.status == 'a_venir') {
        nextMatch ??= match;
      } else {
        lastMatch = match; // écrasé jusqu'au plus récent (tri croissant)
      }

      if (match.status == 'a_venir' &&
          match.kickoffAt != null &&
          !match.predictionsClosed &&
          now.isBefore(
            match.kickoffAt!.subtract(const Duration(minutes: 5)),
          ) &&
          filledByMatch[match.id] != true) {
        pendingPredictions++;
      }
    }

    var predictionParticipantCount = 0;
    if (nextMatch != null) {
      final count = await _client.rpc(
        'match_prediction_participant_count',
        params: {'p_match_id': nextMatch.id},
      );
      predictionParticipantCount = (count as num?)?.toInt() ?? 0;
    }

    final recentMeetings = <RecentMeeting>[];
    final opponentIdForHistory = nextMatch?.opponentId;
    if (opponentIdForHistory != null) {
      final history = await _client
          .from('matches')
          .select('match_date, score_as_grinta, score_adverse')
          .eq('opponent_id', opponentIdForHistory)
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
      nextMatch: nextMatch,
      lastMatch: lastMatch,
      pendingPredictions: pendingPredictions,
      predictionParticipantCount: predictionParticipantCount,
      recentMeetings: recentMeetings,
    );
  }
}

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  return HomeRepository(ref.watch(supabaseClientProvider));
});

// Mis en cache (pas d'autoDispose) : l'accueil s'affiche instantanément sans
// écran de chargement à chaque visite. Le tableau de bord est réinvalidé
// explicitement quand un match change (création, modification, résultat), donc
// un nouveau match apparaît quand même tout de suite.
final homeDashboardProvider = FutureProvider<HomeDashboardData>((ref) {
  return ref.watch(homeRepositoryProvider).fetchDashboard();
});
