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

  bool isPredictionTimeOpenAt(DateTime now) =>
      status == 'a_venir' &&
      kickoffAt != null &&
      !predictionsClosed &&
      now.isBefore(kickoffAt!.subtract(const Duration(minutes: 5)));

  bool get hasOdds => oddsWin != null && oddsDraw != null && oddsLoss != null;
}

class HomeDashboardData {
  const HomeDashboardData({
    required this.nextMatch,
    required this.lastMatch,
    required this.pendingPredictions,
    required this.predictionParticipantCount,
    required this.recentMeetings,
    required this.nextMatchPredicted,
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

  /// La personne a-t-elle déjà rempli son prono pour le prochain match ?
  final bool nextMatchPredicted;
}

class HomeRepository {
  HomeRepository(this._client);

  final SupabaseClient _client;

  HomeMatch _toMatch(Map<String, dynamic> map) {
    final opponent = map['opponents'] is Map
        ? Map<String, dynamic>.from(map['opponents'] as Map)
        : const <String, dynamic>{};
    final serverKickoff = DateTime.tryParse(
      '${map['kickoff_at'] ?? ''}',
    )?.toLocal();
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
      kickoffAt: serverKickoff ?? DateTime.tryParse('${date}T$time'),
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
          'id, opponent_id, match_date, match_time, kickoff_at, location, status, '
          'score_as_grinta, score_adverse, predictions_closed_at, '
          'opponents(name), '
          'match_odds(odds_victoire_as_grinta, odds_nul, odds_victoire_adverse)',
        )
        .inFilter('status', const ['a_venir', 'termine', 'archive']).order(
            'kickoff_at',
            ascending: true);

    final predictions = await _client
        .from('match_predictions')
        .select('match_id, is_filled')
        .eq('profile_id', userId);
    final filledByMatch = <String, bool>{};
    for (final row in predictions as List) {
      final map = Map<String, dynamic>.from(row);
      filledByMatch[map['match_id'].toString()] = map['is_filled'] == true;
    }

    final matches = (rows as List)
        .map((row) => _toMatch(Map<String, dynamic>.from(row as Map)))
        .toList();
    final now = DateTime.now();
    String? firstOpenMatchId;
    for (final match in matches) {
      if (match.isPredictionTimeOpenAt(now)) {
        firstOpenMatchId = match.id;
        break;
      }
    }

    HomeMatch? nextMatch;
    HomeMatch? lastMatch;
    var pendingPredictions = 0;

    for (final match in matches) {
      // Prochain match : le premier « à venir » (liste triée par date
      // croissante). Dernier joué : le plus récent terminé/archivé.
      if (match.status == 'a_venir') {
        nextMatch ??= match;
      } else {
        lastMatch = match; // écrasé jusqu'au plus récent (tri croissant)
      }

      if (match.id == firstOpenMatchId && filledByMatch[match.id] != true) {
        pendingPredictions = 1;
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
      nextMatchPredicted:
          nextMatch != null && filledByMatch[nextMatch.id] == true,
    );
  }
}

/// Le dernier pronostic de match rempli par la personne connectée, sur un match
/// désormais terminé (pour le bloc « Ton dernier prono » de l'accueil).
class LastProno {
  const LastProno({
    required this.matchId,
    required this.opponent,
    required this.isHome,
    required this.grintaScore,
    required this.opponentScore,
    required this.predGrinta,
    required this.predAdverse,
    required this.useX2,
    required this.points,
    required this.kickoffAt,
  });

  final String matchId;
  final String opponent;
  final bool isHome;

  /// Score réel du match.
  final int grintaScore;
  final int opponentScore;

  /// Score pronostiqué.
  final int predGrinta;
  final int predAdverse;
  final bool useX2;
  final double points;
  final DateTime? kickoffAt;

  bool get isWin => grintaScore > opponentScore;
  bool get isDraw => grintaScore == opponentScore;

  /// Bon vainqueur : le sens du résultat pronostiqué correspond au sens réel.
  bool get goodWinner =>
      predGrinta.compareTo(predAdverse).sign ==
      grintaScore.compareTo(opponentScore).sign;

  /// Score exact trouvé.
  bool get exact => predGrinta == grintaScore && predAdverse == opponentScore;
}

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  return HomeRepository(ref.watch(supabaseClientProvider));
});

/// Dernier prono de match de la personne connectée (sur un match terminé).
final myLastPronoProvider = FutureProvider<LastProno?>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final uid = client.auth.currentUser?.id;
  if (uid == null) return null;

  final rows = await client
      .from('match_predictions')
      .select(
        'predicted_score_as_grinta, predicted_score_adverse, use_x2, match_id, '
        'matches!inner(id, score_as_grinta, score_adverse, location, '
        'match_date, match_time, kickoff_at, status, opponents(name))',
      )
      .eq('profile_id', uid)
      .eq('is_filled', true)
      .inFilter('matches.status', const ['termine', 'archive']);

  // On sélectionne côté client le match terminé le plus récent (PostgREST ne
  // trie pas la racine par une colonne d'une table liée).
  Map<String, dynamic>? best;
  DateTime bestKickoff = DateTime(0);
  for (final row in rows as List) {
    final map = Map<String, dynamic>.from(row as Map);
    final match = map['matches'] is Map
        ? Map<String, dynamic>.from(map['matches'] as Map)
        : const <String, dynamic>{};
    final grinta = (match['score_as_grinta'] as num?)?.toInt();
    final opponent = (match['score_adverse'] as num?)?.toInt();
    if (grinta == null || opponent == null) continue;
    final serverKickoff = DateTime.tryParse(
      '${match['kickoff_at'] ?? ''}',
    )?.toLocal();
    final date = match['match_date']?.toString() ?? '';
    final time = match['match_time']?.toString() ?? '00:00:00';
    final kickoff =
        serverKickoff ?? DateTime.tryParse('${date}T$time') ?? DateTime(0);
    if (best == null || kickoff.isAfter(bestKickoff)) {
      best = map;
      bestKickoff = kickoff;
    }
  }
  if (best == null) return null;

  final match = Map<String, dynamic>.from(best['matches'] as Map);
  final matchId = match['id'].toString();

  final pointsRows = await client
      .from('v_match_prediction_points')
      .select('points')
      .eq('profile_id', uid)
      .eq('match_id', matchId)
      .limit(1);
  final points = (pointsRows as List).isNotEmpty
      ? ((Map<String, dynamic>.from(pointsRows.first as Map)['points'] as num?)
              ?.toDouble() ??
          0)
      : 0.0;

  final opp = match['opponents'] is Map
      ? Map<String, dynamic>.from(match['opponents'] as Map)
      : const <String, dynamic>{};

  return LastProno(
    matchId: matchId,
    opponent: opp['name']?.toString() ?? 'Adversaire',
    isHome: (match['location']?.toString() ?? 'domicile') == 'domicile',
    grintaScore: (match['score_as_grinta'] as num).toInt(),
    opponentScore: (match['score_adverse'] as num).toInt(),
    predGrinta: (best['predicted_score_as_grinta'] as num?)?.toInt() ?? 0,
    predAdverse: (best['predicted_score_adverse'] as num?)?.toInt() ?? 0,
    useX2: best['use_x2'] == true,
    points: points,
    kickoffAt: bestKickoff.year > 1 ? bestKickoff : null,
  );
});

// Mis en cache (pas d'autoDispose) : l'accueil s'affiche instantanément sans
// écran de chargement à chaque visite. Le tableau de bord est réinvalidé
// explicitement quand un match change (création, modification, résultat), donc
// un nouveau match apparaît quand même tout de suite.
final homeDashboardProvider = FutureProvider<HomeDashboardData>((ref) {
  return ref.watch(homeRepositoryProvider).fetchDashboard();
});
