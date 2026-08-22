import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Disponibilité du bilan de saison.
///
/// Le bouton n'apparaît qu'entre deux saisons : dès qu'une nouvelle saison
/// est créée, la base cesse de servir le bilan et `available` repasse à faux.
class SeasonWrappedState {
  const SeasonWrappedState({
    required this.available,
    this.seasonName,
  });

  const SeasonWrappedState.unavailable()
      : available = false,
        seasonName = null;

  factory SeasonWrappedState.fromJson(Map<String, dynamic> json) {
    return SeasonWrappedState(
      available: json['available'] == true,
      seasonName: json['season_name']?.toString(),
    );
  }

  final bool available;
  final String? seasonName;
}

/// Un critère du bilan.
///
/// `rank` est nul quand le critère n'est pas classé : soit parce qu'il ne se
/// classe pas par nature (poste, détail victoires/nuls/défaites), soit parce
/// que le joueur n'atteint pas le nombre de matchs exigé pour une moyenne.
class SeasonWrappedStat {
  const SeasonWrappedStat({
    required this.label,
    required this.value,
    this.rank,
    this.note,
  });

  final String label;
  final String value;
  final int? rank;
  final String? note;

  bool get isRanked => rank != null;
}

/// Une feuille du bilan : plusieurs critères qui se partagent en une image.
class SeasonWrappedSheet {
  const SeasonWrappedSheet({
    required this.title,
    required this.stats,
  });

  final String title;
  final List<SeasonWrappedStat> stats;
}

class SeasonWrapped {
  const SeasonWrapped({
    required this.seasonName,
    required this.rosterSize,
    required this.matchesPlayed,
    required this.matchesPlayedRank,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.winPct,
    required this.winPctRank,
    required this.winPctPool,
    required this.avgResponseHours,
    required this.avgResponseRank,
    required this.avgResponsePool,
    required this.goals,
    required this.goalsRank,
    required this.motm,
    required this.motmRank,
    required this.cleanMatches,
    required this.cleanMatchesRank,
    required this.versatility,
    required this.versatilityRank,
    required this.topPosition,
  });

  factory SeasonWrapped.fromJson(Map<String, dynamic> json) {
    int asInt(String key) => (json[key] as num?)?.toInt() ?? 0;
    int? asNullableInt(String key) => (json[key] as num?)?.toInt();
    double? asNullableDouble(String key) => (json[key] as num?)?.toDouble();

    return SeasonWrapped(
      seasonName: json['season_name']?.toString() ?? '',
      rosterSize: asInt('roster_size'),
      matchesPlayed: asInt('matches_played'),
      matchesPlayedRank: asNullableInt('matches_played_rank'),
      wins: asInt('wins'),
      draws: asInt('draws'),
      losses: asInt('losses'),
      winPct: asNullableDouble('win_pct'),
      winPctRank: asNullableInt('win_pct_rank'),
      winPctPool: asNullableInt('win_pct_pool'),
      avgResponseHours: asNullableDouble('avg_response_hours'),
      avgResponseRank: asNullableInt('avg_response_rank'),
      avgResponsePool: asNullableInt('avg_response_pool'),
      goals: asInt('goals'),
      goalsRank: asNullableInt('goals_rank'),
      motm: asInt('motm'),
      motmRank: asNullableInt('motm_rank'),
      cleanMatches: asInt('clean_matches'),
      cleanMatchesRank: asNullableInt('clean_matches_rank'),
      versatility: asInt('versatility'),
      versatilityRank: asNullableInt('versatility_rank'),
      topPosition: json['top_position']?.toString(),
    );
  }

  final String seasonName;
  final int rosterSize;
  final int matchesPlayed;
  final int? matchesPlayedRank;
  final int wins;
  final int draws;
  final int losses;
  final double? winPct;
  final int? winPctRank;
  final int? winPctPool;
  final double? avgResponseHours;
  final int? avgResponseRank;
  final int? avgResponsePool;
  final int goals;
  final int? goalsRank;
  final int motm;
  final int? motmRank;
  final int cleanMatches;
  final int? cleanMatchesRank;
  final int versatility;
  final int? versatilityRank;
  final String? topPosition;

  /// Les neuf critères, répartis en trois feuilles partageables.
  ///
  /// Une feuille par thème plutôt qu'une image par chiffre : trois images se
  /// regardent, neuf se subissent. Trois critères chacune, pour que les trois
  /// images aient la même allure.
  List<SeasonWrappedSheet> get sheets {
    return [
      SeasonWrappedSheet(
        title: 'Ma présence',
        stats: [
          SeasonWrappedStat(
            label: 'Matchs joués',
            value: '$matchesPlayed',
            rank: matchesPlayedRank,
          ),
          SeasonWrappedStat(
            label: 'Réactivité aux disponibilités',
            value: avgResponseHours == null
                ? 'Aucune réponse'
                : _formatDelay(avgResponseHours!),
            rank: avgResponseRank,
            note: avgResponseHours != null && avgResponseRank == null
                ? 'Non classé : moins de huit réponses.'
                : null,
          ),
          SeasonWrappedStat(
            label: 'Poste le plus joué',
            value: topPosition ?? 'Jamais aligné au coup d’envoi',
          ),
        ],
      ),
      SeasonWrappedSheet(
        title: 'Mon apport',
        stats: [
          SeasonWrappedStat(
            label: 'Buts',
            value: '$goals',
            rank: goalsRank,
          ),
          SeasonWrappedStat(
            label: 'Homme du match',
            value: '$motm',
            rank: motmRank,
          ),
          SeasonWrappedStat(
            label: 'Polyvalence',
            value:
                versatility <= 1 ? '$versatility poste' : '$versatility postes',
            rank: versatilityRank,
          ),
        ],
      ),
      SeasonWrappedSheet(
        title: 'Mes résultats',
        stats: [
          SeasonWrappedStat(
            label: 'Victoires, nuls, défaites',
            value: '$wins V · $draws N · $losses D',
          ),
          SeasonWrappedStat(
            label: 'Pourcentage de victoire',
            value: winPct == null ? '—' : '${_formatNumber(winPct!)} %',
            rank: winPctRank,
            note: winPctRank == null && matchesPlayed > 0
                ? 'Non classé : moins de huit matchs joués.'
                : null,
          ),
          SeasonWrappedStat(
            label: 'Matchs sans encaisser',
            value: '$cleanMatches',
            rank: cleanMatchesRank,
          ),
        ],
      ),
    ];
  }

  /// Tous les critères, feuilles confondues.
  List<SeasonWrappedStat> get stats =>
      [for (final sheet in sheets) ...sheet.stats];

  static String _formatNumber(double value) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.005) return rounded.toStringAsFixed(0);
    return value.toStringAsFixed(1).replaceAll('.', ',');
  }

  /// Un délai de réponse se lit mieux en jours dès qu'il dépasse la journée.
  static String _formatDelay(double hours) {
    if (hours < 1) {
      final minutes = (hours * 60).round();
      return '$minutes min';
    }
    if (hours < 48) return '${_formatNumber(hours)} h';
    final days = hours / 24;
    return '${_formatNumber(days)} jours';
  }
}

class SeasonWrappedRepository {
  SeasonWrappedRepository(this._client);

  final SupabaseClient _client;

  Future<SeasonWrappedState> fetchState() async {
    final response = await _client.rpc('get_season_wrapped_state');
    if (response is! Map) return const SeasonWrappedState.unavailable();
    return SeasonWrappedState.fromJson(Map<String, dynamic>.from(response));
  }

  Future<SeasonWrapped?> fetchMine() async {
    final response = await _client.rpc('get_my_season_wrapped');
    if (response is! Map) return null;
    return SeasonWrapped.fromJson(Map<String, dynamic>.from(response));
  }
}

final seasonWrappedRepositoryProvider =
    Provider<SeasonWrappedRepository>((ref) {
  return SeasonWrappedRepository(ref.watch(supabaseClientProvider));
});

final seasonWrappedStateProvider =
    FutureProvider<SeasonWrappedState>((ref) async {
  return ref.watch(seasonWrappedRepositoryProvider).fetchState();
});

final mySeasonWrappedProvider = FutureProvider<SeasonWrapped?>((ref) async {
  return ref.watch(seasonWrappedRepositoryProvider).fetchMine();
});
