import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/utils/name_validation.dart';
import 'package:as_grinta/features/badges/data/badge_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Désigne le joueur dont on ouvre la fiche.
///
/// Les statistiques relient un joueur d'une saison à l'autre par son nom
/// complet et son poste ; un compte, quand il existe, l'identifie plus sûrement
/// encore. Le classement des pronostics ne connaît que le compte : la clé
/// accepte donc l'un ou l'autre, ou les deux.
typedef PlayerCardKey = ({
  String? profileId,
  String fullName,
  bool isGoalkeeper,
});

/// Un match validé auquel le joueur a pris part.
class PlayerMatchLine {
  const PlayerMatchLine({
    required this.matchId,
    required this.date,
    required this.opponentName,
    required this.grintaScore,
    required this.opponentScore,
    required this.isHome,
    required this.matchType,
    required this.goals,
    required this.assists,
    required this.isManOfTheMatch,
  });

  final String matchId;
  final DateTime date;
  final String opponentName;
  final int grintaScore;
  final int opponentScore;
  final bool isHome;
  final String? matchType;
  final int goals;
  final int assists;
  final bool isManOfTheMatch;

  /// « V », « N » ou « D », vu d'AS La Grinta.
  String get result => grintaScore > opponentScore
      ? 'V'
      : grintaScore == opponentScore
          ? 'N'
          : 'D';
}

/// Ce que la fiche affiche en plus des statistiques par période : l'identité
/// du joueur dans l'effectif et ses derniers matchs suivis dans l'application.
class PlayerCardDetails {
  const PlayerCardDetails({
    required this.displayName,
    required this.photoUrl,
    required this.profileId,
    required this.recentMatches,
  });

  /// `null` quand aucune fiche d'effectif ne correspond (par exemple un
  /// pronostiqueur qui ne joue pas).
  final String? displayName;
  final String? photoUrl;
  final String? profileId;

  /// Du plus récent au plus ancien.
  final List<PlayerMatchLine> recentMatches;
}

class PlayerCardRepository {
  PlayerCardRepository(this._client);

  final SupabaseClient _client;

  static const recentMatchLimit = 10;

  Future<PlayerCardDetails> fetch(PlayerCardKey key) async {
    final rows = await _client.from('season_players').select('''
      id,
      first_name,
      last_name,
      is_goalkeeper,
      is_coach,
      profile_id,
      photo_url,
      player_id,
      joined_at,
      profiles!season_players_profile_id_fkey(first_name, surnom, photo_url)
    ''');

    final wantedName = _normalize(key.fullName);
    final all = [
      for (final raw in rows as List) Map<String, dynamic>.from(raw as Map),
    ];
    final found = all.where((row) {
      if (row['is_coach'] == true) return false;
      final profileId = row['profile_id']?.toString();
      if (key.profileId != null && profileId == key.profileId) return true;
      if (wantedName.isEmpty) return false;
      final fullName = _normalize(
        '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}',
      );
      return fullName == wantedName &&
          (row['is_goalkeeper'] == true) == key.isGoalkeeper;
    });
    // `player_id` suit la même personne d'une saison à l'autre : on récupère
    // ainsi ses saisons passées même s'il a changé de nom ou de compte.
    final playerIds = {
      for (final row in found)
        if (row['player_id'] != null) row['player_id'].toString(),
    };
    final foundIds = {for (final row in found) row['id'].toString()};
    final matching = all
        .where(
          (row) =>
              foundIds.contains(row['id'].toString()) ||
              playerIds.contains(row['player_id']?.toString()),
        )
        .toList()
      // La fiche la plus récente porte le nom et la photo d'aujourd'hui.
      ..sort(
        (a, b) => (b['joined_at'] ?? '')
            .toString()
            .compareTo((a['joined_at'] ?? '').toString()),
      );

    if (matching.isEmpty) {
      return PlayerCardDetails(
        displayName: null,
        photoUrl: null,
        profileId: key.profileId,
        recentMatches: const [],
      );
    }

    final latest = matching.first;
    final profile = latest['profiles'] is Map
        ? Map<String, dynamic>.from(latest['profiles'] as Map)
        : const <String, dynamic>{};

    return PlayerCardDetails(
      displayName: _displayName(latest, profile),
      photoUrl: _firstNonEmpty(profile['photo_url'], latest['photo_url']),
      profileId: latest['profile_id']?.toString() ?? key.profileId,
      recentMatches: await _recentMatches([
        for (final row in matching) row['id'].toString(),
      ]),
    );
  }

  Future<List<PlayerMatchLine>> _recentMatches(List<String> ids) async {
    // Même définition de « match joué » que les statistiques : présent,
    // auteur d'une ligne de stats ou élu homme du match.
    final results = await Future.wait([
      _client
          .from('match_player_stats')
          .select('match_id, goals, assists')
          .inFilter('season_player_id', ids),
      _client
          .from('match_man_of_match')
          .select('match_id')
          .inFilter('season_player_id', ids),
      _client
          .from('match_attendance')
          .select('match_id')
          .inFilter('season_player_id', ids),
    ]);

    final goals = <String, int>{};
    final assists = <String, int>{};
    for (final raw in results[0] as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final id = row['match_id'].toString();
      goals[id] = (goals[id] ?? 0) + ((row['goals'] as num?)?.toInt() ?? 0);
      assists[id] =
          (assists[id] ?? 0) + ((row['assists'] as num?)?.toInt() ?? 0);
    }
    final motm = {
      for (final raw in results[1] as List) (raw as Map)['match_id'].toString(),
    };
    final matchIds = {
      ...goals.keys,
      ...motm,
      for (final raw in results[2] as List) (raw as Map)['match_id'].toString(),
    };
    if (matchIds.isEmpty) return const [];

    final matches = await _client
        .from('matches')
        .select('''
          id, match_date, match_type, location, score_as_grinta, score_adverse,
          opponents(name)
        ''')
        .inFilter('id', matchIds.toList())
        .inFilter('status', ['termine', 'archive'])
        .order('match_date', ascending: false)
        .limit(recentMatchLimit);

    return [
      for (final raw in matches as List)
        _matchLine(
          Map<String, dynamic>.from(raw as Map),
          goals: goals,
          assists: assists,
          motm: motm,
        ),
    ];
  }

  PlayerMatchLine _matchLine(
    Map<String, dynamic> row, {
    required Map<String, int> goals,
    required Map<String, int> assists,
    required Set<String> motm,
  }) {
    final id = row['id'].toString();
    final opponent = row['opponents'] is Map
        ? (row['opponents'] as Map)['name']?.toString()
        : null;
    return PlayerMatchLine(
      matchId: id,
      date: DateTime.tryParse('${row['match_date']}') ?? DateTime(1970),
      opponentName: (opponent == null || opponent.trim().isEmpty)
          ? 'Adversaire'
          : opponent.trim(),
      grintaScore: (row['score_as_grinta'] as num?)?.toInt() ?? 0,
      opponentScore: (row['score_adverse'] as num?)?.toInt() ?? 0,
      isHome: row['location']?.toString() != 'exterieur',
      matchType: row['match_type']?.toString(),
      goals: goals[id] ?? 0,
      assists: assists[id] ?? 0,
      isManOfTheMatch: motm.contains(id),
    );
  }

  // Même priorité que l'effectif : surnom, puis prénom du compte, puis prénom
  // saisi par l'admin.
  String _displayName(Map<String, dynamic> row, Map<String, dynamic> profile) {
    for (final candidate in [
      profile['surnom'],
      profile['first_name'],
      row['first_name'],
      row['last_name'],
    ]) {
      final name = capitalizePersonName(candidate?.toString() ?? '');
      if (name.isNotEmpty) return name;
    }
    return 'Joueur';
  }

  String? _firstNonEmpty(Object? a, Object? b) {
    for (final value in [a, b]) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

final playerCardRepositoryProvider = Provider<PlayerCardRepository>((ref) {
  return PlayerCardRepository(ref.watch(supabaseClientProvider));
});

final playerCardDetailsProvider =
    FutureProvider.autoDispose.family<PlayerCardDetails, PlayerCardKey>(
  (ref, key) => ref.watch(playerCardRepositoryProvider).fetch(key),
);

/// Badges gagnés par un autre membre, tels qu'on peut les montrer sur sa
/// fiche.
///
/// Tous les badges gagnés apparaissent, secrets compris : un secret ne l'est
/// que tant qu'il n'est pas gagné. Le chiffre personnel d'un badge (cumul
/// réel, record de saison) n'est lisible que par son titulaire : un palier
/// affiche donc son propre seuil, et un titre n'affiche pas de chiffre.
List<ArmoireBadge> publicEarnedBadges({
  required List<BadgeDef> catalog,
  required Map<String, DateTime> earnedAt,
}) {
  return [
    for (final def in catalog)
      if (earnedAt.containsKey(def.code))
        ArmoireBadge(
          def: def,
          state: BadgeState.validated,
          displayValue: def.kind == 'tier' ? def.threshold : null,
          awardedAt: earnedAt[def.code],
        ),
  ]..sort((a, b) => a.def.sortOrder.compareTo(b.def.sortOrder));
}

/// Les badges gagnés par le titulaire du compte [profileId].
///
/// Sur sa propre fiche, le joueur retrouve exactement ses badges validés de
/// l'armoire, secrets, chiffres et étoiles compris.
final playerCardBadgesProvider =
    FutureProvider.autoDispose.family<List<ArmoireBadge>, String>(
  (ref, profileId) async {
    final client = ref.watch(supabaseClientProvider);
    final badges = ref.watch(badgeRepositoryProvider);
    if (client.auth.currentUser?.id == profileId) {
      return (await badges.fetchArmoire(profileId)).validated;
    }
    final catalog = await badges.fetchCatalog();
    final rows = await client
        .from('profile_badges')
        .select('awarded_at, badges(code)')
        .eq('profile_id', profileId);
    final earnedAt = <String, DateTime>{};
    for (final raw in rows as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final badge = row['badges'];
      final code = badge is Map ? badge['code']?.toString() : null;
      if (code == null) continue;
      earnedAt[code] =
          DateTime.tryParse(row['awarded_at']?.toString() ?? '') ?? DateTime(0);
    }
    return publicEarnedBadges(catalog: catalog, earnedAt: earnedAt);
  },
);
