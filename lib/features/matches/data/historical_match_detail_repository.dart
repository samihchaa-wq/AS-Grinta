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
    this.lastInitial,
    this.isVacant = false,
  });

  final String name;

  /// Initiale du nom de famille, tirée du nom complet gardé par l'archive :
  /// l'écran n'affiche qu'un prénom, mais la pastille sans photo doit quand
  /// même distinguer deux joueurs au même prénom.
  final String? lastInitial;
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
    required this.scorers,
    required this.motmNames,
    this.archiveNameByLabel = const {},
  });

  final String? formation;
  final List<HistoricalFieldPlayer> fieldPlayers;
  final List<HistoricalFieldPlayer> benchPlayers;
  final List<String> presentNames;
  final List<HistoricalScorer> scorers;
  final List<String> motmNames;

  /// Nom écrit sur la feuille de match d'origine, par appellation affichée.
  /// L'écran garde ainsi de quoi reconnaître un joueur d'archive même quand
  /// l'application l'appelle désormais par son surnom.
  final Map<String, String> archiveNameByLabel;

  /// Une composition n'a de sens que si l'archive connaît au moins un nom :
  /// un terrain rempli uniquement d'emplacements vides n'apprendrait rien,
  /// la fiche bascule alors sur sa simple liste de joueurs.
  bool get hasComposition => fieldPlayers.any((player) => !player.isVacant);
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
  final motmNamesRaw = stringList(row['motm_names']);
  final photoUrlsByName = Map<String, dynamic>.from(
    row['photo_urls'] as Map? ?? const {},
  );
  final identitiesByName = Map<String, dynamic>.from(
    row['display_names'] as Map? ?? const {},
  );

  // L'archive stocke le nom complet écrit sur la vieille feuille de match, où
  // un joueur a pu être noté sous son surnom et un autre sous son prénom. Le
  // Calendrier appelle tout le monde par son surnom : on part donc de
  // l'identité du club quand l'archive est reliée à un joueur connu, et on
  // retombe sur le prénom de la feuille sinon. Les homonymes reçoivent
  // l'initiale de leur nom, comme ailleurs. Les emplacements vides n'entrent
  // pas dans le calcul : ce ne sont pas des joueurs.
  final archiveNames = {
    ...fieldPlayersRaw
        .map((entry) => (entry['name'] ?? '').toString())
        .where((name) => !isVacantArchiveSlotName(name)),
    ...benchPlayersRaw,
    ...presentNamesRaw,
  };
  final identity = _ArchiveIdentities(identitiesByName);
  final shortName = _shortNameResolver(archiveNames, identity);
  final archiveNameByLabel = {
    for (final archiveName in archiveNames) shortName(archiveName): archiveName,
  };

  final fieldPlayers = fieldPlayersRaw.map(
    (entry) {
      final fullName = (entry['name'] ?? '').toString();
      final isVacant = isVacantArchiveSlotName(fullName);
      return HistoricalFieldPlayer(
        name: isVacant ? '' : shortName(fullName),
        lastInitial: isVacant ? null : identity.lastInitialOf(fullName),
        positionLabel: (entry['position_label'] ?? '').toString(),
        xPct: (entry['x_pct'] as num?)?.toDouble() ?? 50,
        yPct: (entry['y_pct'] as num?)?.toDouble() ?? 50,
        isGoalkeeper: entry['is_gk'] as bool? ?? false,
        photoUrl: isVacant ? null : photoUrlsByName[fullName] as String?,
        isVacant: isVacant,
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
          lastInitial: identity.lastInitialOf(fullName),
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
    scorers: scorers,
    motmNames: motmNamesRaw.map(shortName).toList(growable: false),
    archiveNameByLabel: archiveNameByLabel,
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

/// Identités du club rattachées aux noms d'une feuille de match archivée :
/// surnom (sinon prénom) et initiale du nom de famille, telles que la base
/// les renvoie. Un joueur que l'archive ne relie à personne n'y figure pas.
class _ArchiveIdentities {
  _ArchiveIdentities(this._byArchiveName);

  final Map<String, dynamic> _byArchiveName;

  String? nameOf(String archiveName) => _read(archiveName, 'name');

  /// Initiale du nom de famille : celle du club si on la connaît, sinon celle
  /// que donne le nom complet de la feuille de match.
  String? lastInitialOf(String archiveName) {
    final initial = _read(archiveName, 'last_initial');
    if (initial != null) return initial.toUpperCase();
    return lastNameInitialOf(archiveName);
  }

  String? _read(String archiveName, String key) {
    final entry = _byArchiveName[archiveName];
    if (entry is! Map) return null;
    final value = (entry[key] ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }
}

/// Construit l'appellation d'un joueur d'archive : son surnom au club quand
/// on le connaît, sinon le prénom écrit sur la feuille de match. Deux joueurs
/// qui finissent avec la même appellation sur un même match reçoivent
/// l'initiale de leur nom : deux « Xavier » deviennent « Xavier G. » et
/// « Xavier L. », sinon un « Xavier » seul reste juste « Xavier ».
String Function(String) _shortNameResolver(
  Iterable<String> archiveNames,
  _ArchiveIdentities identities,
) {
  String label(String archiveName) =>
      identities.nameOf(archiveName) ?? firstNameOf(archiveName);

  final labelCounts = <String, int>{};
  for (final archiveName in archiveNames) {
    final key = label(archiveName).toLowerCase();
    if (key.isEmpty) continue;
    labelCounts[key] = (labelCounts[key] ?? 0) + 1;
  }
  return (archiveName) {
    final name = label(archiveName);
    final isHomonym = (labelCounts[name.toLowerCase()] ?? 0) > 1;
    final lastInitial = identities.lastInitialOf(archiveName);
    return isHomonym && lastInitial != null ? '$name $lastInitial.' : name;
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
