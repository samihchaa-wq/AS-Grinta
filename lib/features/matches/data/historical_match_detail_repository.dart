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
    this.isVacant = false,
  });

  final String name;
  final String positionLabel;
  final double xPct;
  final double yPct;
  final bool isGoalkeeper;
  final String? photoUrl;

  /// Emplacement du schéma dont l'archive ne connaît pas le joueur : la
  /// vieille feuille de match donne la formation mais pas tous les noms.
  final bool isVacant;
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
    required this.absentNames,
    required this.scorers,
    required this.motmNames,
  });

  final String? formation;
  final List<HistoricalFieldPlayer> fieldPlayers;
  final List<HistoricalFieldPlayer> benchPlayers;
  final List<String> presentNames;

  /// `null` signifie que la source historique ne permet pas de connaître les
  /// absents. Une liste vide signifie au contraire « aucun absent » de façon
  /// explicite. Cette distinction évite d'afficher un faux effectif complet.
  final List<String>? absentNames;
  final List<HistoricalScorer> scorers;
  final List<String> motmNames;

  /// Une composition n'a de sens que si l'archive connaît au moins un nom :
  /// un terrain rempli uniquement d'emplacements vides n'apprendrait rien,
  /// la fiche bascule alors sur sa simple liste de joueurs.
  bool get hasComposition => fieldPlayers.any((player) => !player.isVacant);
  bool get isEmpty =>
      formation == null &&
      fieldPlayers.isEmpty &&
      benchPlayers.isEmpty &&
      presentNames.isEmpty &&
      absentNames?.isNotEmpty != true &&
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
    return historicalMatchDetailFromRow(rows.first);
  }
}

/// Traduction d'une ligne d'archive en [HistoricalMatchDetail], isolée du
/// réseau pour rester testable telle quelle.
HistoricalMatchDetail historicalMatchDetailFromRow(Map<String, dynamic> row) {
  final fieldPlayersRaw = (row['field_players'] as List? ?? const [])
      .map((entry) => Map<String, dynamic>.from(entry as Map))
      .toList(growable: false);
  final scorersRaw = (row['scorers'] as List? ?? const [])
      .map((entry) => Map<String, dynamic>.from(entry as Map))
      .toList(growable: false);

  List<String> stringList(Object? value) => (value as List? ?? const [])
      .map((e) => e.toString())
      .where((name) => !isVacantArchiveSlotName(name))
      .toList(growable: false);
  final benchPlayersRaw = stringList(row['bench_players']);
  final presentNamesRaw = stringList(row['present_names']);
  final absentNamesRaw = row['absent_names'] == null
      ? null
      : stringList(row['absent_names']);
  final motmNamesRaw = stringList(row['motm_names']);
  final photoUrlsByName = Map<String, dynamic>.from(
    row['photo_urls'] as Map? ?? const {},
  );

  // L'archive stocke le nom complet des joueurs, contrairement aux matchs
  // courants où l'appli n'expose que le prénom (lié au profil). On applique
  // ici la même réduction « prénom, + initiale du nom si homonyme exact »
  // que la page Statistiques, pour que la composition d'un match archivé se
  // lise exactement comme celle d'un match courant. Les emplacements vides
  // n'entrent pas dans le calcul : ce ne sont pas des joueurs.
  final shortName = _shortNameResolver({
    ...fieldPlayersRaw
        .map((entry) => (entry['name'] ?? '').toString())
        .where((name) => !isVacantArchiveSlotName(name)),
    ...benchPlayersRaw,
    ...presentNamesRaw,
    ...(absentNamesRaw ?? const <String>[]),
  });

  final fieldPlayers = fieldPlayersRaw
      .map((entry) {
        final fullName = (entry['name'] ?? '').toString();
        final isVacant = isVacantArchiveSlotName(fullName);
        return HistoricalFieldPlayer(
          name: isVacant ? '' : shortName(fullName),
          positionLabel: (entry['position_label'] ?? '').toString(),
          xPct: (entry['x_pct'] as num?)?.toDouble() ?? 50,
          yPct: (entry['y_pct'] as num?)?.toDouble() ?? 50,
          isGoalkeeper: entry['is_gk'] as bool? ?? false,
          photoUrl: isVacant ? null : photoUrlsByName[fullName] as String?,
          isVacant: isVacant,
        );
      })
      .toList(growable: false);

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
      .where(
        (entry) => !isVacantArchiveSlotName((entry['name'] ?? '').toString()),
      )
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
    absentNames: absentNamesRaw?.map(shortName).toList(growable: false),
    scorers: scorers,
    motmNames: motmNamesRaw.map(shortName).toList(growable: false),
  );
}

/// Vrai pour le faux joueur « Poste laissé vide » que l'import d'archives
/// place aux emplacements dont la feuille de match ne donne pas le nom du
/// joueur. Sans ce filtre, l'appli le raccourcirait en « Poste » et
/// l'afficherait comme un joueur à part entière. La base applique la même
/// règle de son côté, ce qui tient déjà ce faux nom hors de l'effectif et
/// des statistiques.
bool isVacantArchiveSlotName(String name) {
  const vacantSlotName = 'poste laisse vide';
  const accents = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ';
  const plain = 'aaaaaaceeeeiiiinooooouuuuyy';
  final buffer = StringBuffer();
  for (final rune in name.trim().toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final accentIndex = accents.indexOf(char);
    buffer.write(accentIndex < 0 ? char : plain[accentIndex]);
  }
  final normalized = buffer.toString().replaceAll(RegExp(r'\s+'), ' ');
  return normalized == vacantSlotName;
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
      (ref) =>
          HistoricalMatchDetailRepository(ref.watch(supabaseClientProvider)),
    );

final historicalMatchDetailProvider =
    FutureProvider.family<HistoricalMatchDetail?, String>((ref, matchId) {
      return ref.watch(historicalMatchDetailRepositoryProvider).fetch(matchId);
    });
