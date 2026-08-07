import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/utils/name_validation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistoricalFieldPlayer {
  const HistoricalFieldPlayer({
    required this.name,
    required this.positionLabel,
    required this.xPct,
    required this.yPct,
    required this.isGoalkeeper,
    required this.photoUrl,
  });

  final String name;
  final String positionLabel;
  final double xPct;
  final double yPct;
  final bool isGoalkeeper;
  final String? photoUrl;
}

class HistoricalScorer {
  const HistoricalScorer({required this.name, required this.goals});

  final String name;
  final int goals;
}

class HistoricalMatchDetail {
  const HistoricalMatchDetail({
    required this.formation,
    required this.fieldPlayers,
    required this.benchPlayers,
    required this.presentNames,
    required this.scorers,
    required this.motmNames,
  });

  final String? formation;
  final List<HistoricalFieldPlayer> fieldPlayers;
  final List<HistoricalFieldPlayer> benchPlayers;
  final List<String> presentNames;
  final List<HistoricalScorer> scorers;
  final List<String> motmNames;

  bool get hasComposition => fieldPlayers.isNotEmpty;
  bool get isEmpty =>
      formation == null &&
      fieldPlayers.isEmpty &&
      benchPlayers.isEmpty &&
      presentNames.isEmpty &&
      scorers.isEmpty &&
      motmNames.isEmpty;
}

class HistoricalMatchDetailRepository {
  HistoricalMatchDetailRepository(this._client);

  final SupabaseClient _client;

  Future<HistoricalMatchDetail?> fetch(String matchId) async {
    final response = await _client.rpc(
      'get_historical_match_detail',
      params: {'p_match_id': matchId},
    );
    final rows = (response as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    if (rows.isEmpty) return null;
    final row = rows.first;

    final fieldPlayersRaw = (row['field_players'] as List? ?? const [])
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList(growable: false);
    final scorersRaw = (row['scorers'] as List? ?? const [])
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList(growable: false);

    List<String> stringList(Object? value) => (value as List? ?? const [])
        .map((e) => e.toString())
        .toList(growable: false);
    final benchPlayersRaw = stringList(row['bench_players']);
    final presentNamesRaw = stringList(row['present_names']);
    final motmNamesRaw = stringList(row['motm_names']);
    final photoUrlsByName = Map<String, dynamic>.from(
      row['photo_urls'] as Map? ?? const {},
    );

    // L'archive stocke le nom complet des joueurs, contrairement aux matchs
    // courants où l'appli n'expose que le prénom (lié au profil). On applique
    // ici la même réduction « prénom, + initiale du nom si homonyme exact »
    // que la page Statistiques, pour que la composition d'un match archivé se
    // lise exactement comme celle d'un match courant.
    final shortName = _shortNameResolver({
      ...fieldPlayersRaw.map((entry) => (entry['name'] ?? '').toString()),
      ...benchPlayersRaw,
      ...presentNamesRaw,
    });

    final fieldPlayers = fieldPlayersRaw.map(
      (entry) {
        final fullName = (entry['name'] ?? '').toString();
        return HistoricalFieldPlayer(
          name: shortName(fullName),
          positionLabel: (entry['position_label'] ?? '').toString(),
          xPct: (entry['x_pct'] as num?)?.toDouble() ?? 50,
          yPct: (entry['y_pct'] as num?)?.toDouble() ?? 50,
          isGoalkeeper: entry['is_gk'] as bool? ?? false,
          photoUrl: photoUrlsByName[fullName] as String?,
        );
      },
    ).toList(growable: false);

    // Le banc n'est stocké que sous forme de noms, contrairement aux
    // titulaires (positions x/y) : on réutilise quand même [HistoricalFieldPlayer]
    // (x/y ignorés hors terrain) pour que la carte de composition partagée
    // affiche la même tuile joueur — avec photo — que sur le terrain.
    final benchPlayers = benchPlayersRaw
        .map(
          (fullName) => HistoricalFieldPlayer(
            name: shortName(fullName),
            positionLabel: '',
            xPct: 50,
            yPct: 50,
            isGoalkeeper: false,
            photoUrl: photoUrlsByName[fullName] as String?,
          ),
        )
        .toList(growable: false);

    final scorers = scorersRaw
        .map(
          (entry) => HistoricalScorer(
            name: shortName((entry['name'] ?? '').toString()),
            goals: (entry['goals'] as num?)?.toInt() ?? 1,
          ),
        )
        .toList(growable: false);

    return HistoricalMatchDetail(
      formation: (row['formation'] as String?),
      fieldPlayers: fieldPlayers,
      benchPlayers: benchPlayers,
      presentNames: presentNamesRaw.map(shortName).toList(growable: false),
      scorers: scorers,
      motmNames: motmNamesRaw.map(shortName).toList(growable: false),
    );
  }
}

/// Construit un « prénom, + initiale si homonyme exact » à partir de
/// l'ensemble des noms complets d'un même match : deux « Xavier » sur la
/// même feuille de match deviennent « Xavier G. » / « Xavier L. », sinon un
/// « Xavier » seul reste juste « Xavier ».
String Function(String) _shortNameResolver(Iterable<String> fullNames) {
  final firstNameCounts = <String, int>{};
  for (final fullName in fullNames) {
    final key = firstNameOf(fullName).toLowerCase();
    if (key.isEmpty) continue;
    firstNameCounts[key] = (firstNameCounts[key] ?? 0) + 1;
  }
  return (fullName) {
    final firstName = firstNameOf(fullName);
    final isHomonym = (firstNameCounts[firstName.toLowerCase()] ?? 0) > 1;
    final lastInitial = lastNameInitialOf(fullName);
    return isHomonym && lastInitial != null
        ? '$firstName $lastInitial.'
        : firstName;
  };
}

final historicalMatchDetailRepositoryProvider =
    Provider<HistoricalMatchDetailRepository>(
  (ref) => HistoricalMatchDetailRepository(ref.watch(supabaseClientProvider)),
);

final historicalMatchDetailProvider =
    FutureProvider.family<HistoricalMatchDetail?, String>((ref, matchId) {
  return ref.watch(historicalMatchDetailRepositoryProvider).fetch(matchId);
});
