import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Disponibilité du bilan de saison.
///
/// Le bouton n'apparaît qu'entre deux saisons : dès qu'une nouvelle saison
/// est créée, la base cesse de servir le bilan et `available` repasse à faux.
class SeasonWrappedState {
  const SeasonWrappedState({required this.available, this.seasonName});

  const SeasonWrappedState.unavailable() : available = false, seasonName = null;

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
    String? shortLabel,
  }) : _shortLabel = shortLabel;

  final String label;
  final String value;
  final int? rank;
  final String? note;
  final String? _shortLabel;

  /// Intitulé court, pour la récapitulation où les neuf lignes doivent tenir
  /// côte à côte sans se faire couper.
  String get shortLabel => _shortLabel ?? label;

  bool get isRanked => rank != null;
}

/// La part de titularisations à un poste.
/// Un badge décroché pendant la saison.
class SeasonWrappedBadge {
  const SeasonWrappedBadge({
    required this.code,
    required this.name,
    required this.emoji,
  });

  factory SeasonWrappedBadge.fromJson(Map<String, dynamic> json) {
    return SeasonWrappedBadge(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      emoji: json['emoji']?.toString() ?? '',
    );
  }

  final String code;
  final String name;
  final String emoji;
}

class SeasonWrappedPosition {
  const SeasonWrappedPosition({required this.position, required this.share});

  factory SeasonWrappedPosition.fromJson(Map<String, dynamic> json) {
    return SeasonWrappedPosition(
      position: json['position']?.toString() ?? '',
      share: (json['share'] as num?)?.toInt() ?? 0,
    );
  }

  final String position;

  /// Pourcentage entier des titularisations du joueur à ce poste.
  final int share;
}

/// Une feuille du bilan : plusieurs critères qui se partagent en une image.
class SeasonWrappedSheet {
  const SeasonWrappedSheet({required this.title, required this.stats});

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
    required this.positionShares,
    required this.badges,
    required this.badgeCount,
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
      positionShares: [
        for (final entry in (json['position_shares'] as List? ?? const []))
          SeasonWrappedPosition.fromJson(
            Map<String, dynamic>.from(entry as Map),
          ),
      ],
      badges: [
        for (final entry in (json['badges'] as List? ?? const []))
          SeasonWrappedBadge.fromJson(Map<String, dynamic>.from(entry as Map)),
      ],
      badgeCount: asInt('badge_count'),
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

  /// Les postes occupés, du plus joué au moins joué.
  final List<SeasonWrappedPosition> positionShares;

  /// Les badges décrochés pendant la saison, du plus ancien au plus récent.
  final List<SeasonWrappedBadge> badges;
  final int badgeCount;

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
            shortLabel: 'Réactivité',
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
            shortLabel: 'Poste',
            value: topPosition ?? 'Jamais aligné au coup d’envoi',
          ),
        ],
      ),
      SeasonWrappedSheet(
        title: 'Mon apport',
        stats: [
          SeasonWrappedStat(label: 'Buts', value: '$goals', rank: goalsRank),
          SeasonWrappedStat(
            label: 'Homme du match',
            value: '$motm',
            rank: motmRank,
          ),
          SeasonWrappedStat(
            label: 'Polyvalence',
            value: versatility <= 1
                ? '$versatility poste'
                : '$versatility postes',
            rank: versatilityRank,
          ),
        ],
      ),
      SeasonWrappedSheet(
        title: 'Mes résultats',
        stats: [
          SeasonWrappedStat(
            label: 'Victoires, nuls, défaites',
            shortLabel: 'Bilan',
            value: '$wins V · $draws N · $losses D',
          ),
          SeasonWrappedStat(
            label: 'Pourcentage de victoire',
            shortLabel: '% de victoire',
            // Un pourcentage de victoire se lit en entier : la décimale
            // n'apprend rien sur une vingtaine de matchs.
            value: winPct == null ? '—' : '${winPct!.round()} %',
            rank: winPctRank,
            note: winPctRank == null && matchesPlayed > 0
                ? 'Non classé : moins de huit matchs joués.'
                : null,
          ),
          SeasonWrappedStat(
            label: 'Matchs sans encaisser',
            shortLabel: 'Sans encaisser',
            value: '$cleanMatches',
            rank: cleanMatchesRank,
          ),
        ],
      ),
    ];
  }

  /// Tous les critères, feuilles confondues.
  /// Le récapitulatif reprend les neuf critères, puis les badges. Ceux-ci ne
  /// sont pas classés : un joueur qui débute en décroche mécaniquement plus
  /// qu'un ancien, le comparatif n'aurait pas de sens.
  List<SeasonWrappedStat> get stats => [
    for (final sheet in sheets) ...sheet.stats,
    SeasonWrappedStat(
      label: 'Badges décrochés',
      shortLabel: 'Badges',
      value: '$badgeCount',
    ),
  ];

  static String _formatDelay(double hours) =>
      WrappedDelay.fromHours(hours).text;
}

/// Un délai de réponse s'écrit en heures et minutes : « 6 h 30 », « 42 min ».
///
/// Le nombre et son unité restent séparés : l'écran du bilan fait défiler le
/// nombre seul, et n'affiche l'unité qu'une fois le défilement terminé.
class WrappedDelay {
  const WrappedDelay({
    required this.figure,
    required this.suffix,
    this.minutes,
  });

  factory WrappedDelay.fromHours(double hours) {
    final total = (hours * 60).round();
    if (total < 60) return WrappedDelay(figure: total, suffix: ' min');

    final reste = total % 60;
    return WrappedDelay(
      figure: total ~/ 60,
      // Les minutes s'écrivent sur deux chiffres : « 6 h 05 », jamais « 6 h 5 ».
      suffix: reste == 0 ? ' h' : ' h ${reste.toString().padLeft(2, '0')}',
      minutes: reste == 0 ? null : reste,
    );
  }

  /// Le nombre mis en avant : les heures, ou les minutes sous l'heure.
  final int figure;

  /// L'unité, minutes comprises quand il y en a : « h 30 ».
  final String suffix;

  /// Les minutes, quand le délai en compte. L'écran du bilan les fait défiler
  /// séparément, une fois les heures arrivées.
  final int? minutes;

  String get text => '$figure$suffix';
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

final seasonWrappedRepositoryProvider = Provider<SeasonWrappedRepository>((
  ref,
) {
  return SeasonWrappedRepository(ref.watch(supabaseClientProvider));
});

final seasonWrappedStateProvider = FutureProvider<SeasonWrappedState>((
  ref,
) async {
  return ref.watch(seasonWrappedRepositoryProvider).fetchState();
});

final mySeasonWrappedProvider = FutureProvider<SeasonWrapped?>((ref) async {
  return ref.watch(seasonWrappedRepositoryProvider).fetchMine();
});

/// Bilan de démonstration, réservé à l'aperçu administrateur.
///
/// Aucune donnée réelle n'existe tant qu'une saison n'a pas été jouée dans
/// l'application. Ces chiffres n'ont donc qu'un rôle : montrer le rendu.
SeasonWrapped demoSeasonWrapped(String seasonName) {
  return SeasonWrapped.fromJson({
    'season_name': seasonName,
    'roster_size': 19,
    'matches_played': 21,
    'matches_played_rank': 3,
    'wins': 12,
    'draws': 4,
    'losses': 5,
    'win_pct': 57.14,
    'win_pct_rank': 5,
    'avg_response_hours': 6.5,
    'avg_response_rank': 2,
    'goals': 9,
    'goals_rank': 4,
    'motm': 2,
    'motm_rank': 3,
    'clean_matches': 8,
    'clean_matches_rank': 1,
    'versatility': 3,
    'versatility_rank': 2,
    'top_position': 'Milieu défensif',
    'position_shares': [
      {'position': 'Milieu défensif', 'share': 52},
      {'position': 'Défenseur central', 'share': 33},
      {'position': 'Milieu', 'share': 15},
    ],
    'badge_count': 4,
    'badges': [
      {'code': 'matches_played__50', 'name': 'Fidèle', 'emoji': '📅'},
      {'code': 'clean_sheets__10', 'name': 'Mur', 'emoji': '🧱'},
      {'code': 'motm__first', 'name': 'Homme du match', 'emoji': '⭐'},
      {'code': 'season_top_scorer', 'name': 'Meilleur buteur', 'emoji': '🥇'},
    ],
  });
}

/// Le nom qui signe le bilan et les images partagées.
///
/// Isolé dans son propre fournisseur pour que l'écran ne dépende pas
/// directement de l'authentification : c'est la seule chose dont il a besoin.
final wrappedPlayerNameProvider = Provider<String?>((ref) {
  return ref.watch(authControllerProvider).profile?.displayName;
});
