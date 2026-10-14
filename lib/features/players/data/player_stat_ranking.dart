import 'package:as_grinta/features/players/data/player_card_repository.dart';
import 'package:as_grinta/features/players/presentation/player_card_link.dart';
import 'package:as_grinta/features/statistics/data/statistics_repository.dart';

/// Les six statistiques de la fiche joueur, chacune ouvrant son classement
/// complet.
enum PlayerStat {
  matches,
  winRate,
  goals,
  assists,
  manOfTheMatch,
  goalsPerMatch;

  /// Libellé de la case sur la fiche, repris en titre du classement.
  String get label => switch (this) {
        PlayerStat.matches => 'Matchs',
        PlayerStat.winRate => 'Victoires',
        PlayerStat.goals => 'Buts',
        PlayerStat.assists => 'Passes D.',
        PlayerStat.manOfTheMatch => 'Homme du match',
        PlayerStat.goalsPerMatch => 'Buts / match',
      };

  /// En-tête de colonne, abrégé comme dans le tableau des Statistiques.
  String get columnLabel => switch (this) {
        PlayerStat.matches => 'J',
        PlayerStat.winRate => '% V',
        PlayerStat.goals => 'B',
        PlayerStat.assists => 'PD',
        PlayerStat.manOfTheMatch => 'HDM',
        PlayerStat.goalsPerMatch => 'B/M',
      };

  /// Nom dans l'adresse de la page.
  String get slug => switch (this) {
        PlayerStat.matches => 'matchs',
        PlayerStat.winRate => 'victoires',
        PlayerStat.goals => 'buts',
        PlayerStat.assists => 'passes',
        PlayerStat.manOfTheMatch => 'hdm',
        PlayerStat.goalsPerMatch => 'buts-par-match',
      };

  /// Une moyenne ne classe que les joueurs assez présents (voir
  /// `averageRankingMinMatches`).
  bool get isAverage =>
      this == PlayerStat.winRate || this == PlayerStat.goalsPerMatch;

  num valueOf(PlayerStatistics p) {
    final played = p.matchesPlayed ?? 0;
    return switch (this) {
      PlayerStat.matches => played,
      PlayerStat.winRate => played == 0 ? 0 : (p.wins ?? 0) * 100 / played,
      PlayerStat.goals => p.goals,
      PlayerStat.assists => p.assists,
      PlayerStat.manOfTheMatch => p.hdm ?? 0,
      PlayerStat.goalsPerMatch => played == 0 ? 0 : p.goals / played,
    };
  }

  /// La valeur telle qu'elle s'affiche : « 75 % », « 1,75 »… Une moyenne
  /// sans match joué n'a pas de valeur.
  String display(PlayerStatistics p) {
    if (isAverage && (p.matchesPlayed ?? 0) == 0) return '–';
    final value = valueOf(p);
    return switch (this) {
      PlayerStat.winRate => '${value.round()} %',
      PlayerStat.goalsPerMatch => value.toStringAsFixed(2).replaceAll('.', ','),
      _ => '$value',
    };
  }

  static PlayerStat? fromSlug(String? slug) {
    for (final stat in values) {
      if (stat.slug == slug) return stat;
    }
    return null;
  }
}

/// Le compte identifie le joueur quand on le connaît ; sinon, comme la vue
/// des statistiques, le nom complet et le poste.
bool isPlayerOfCard(PlayerStatistics player, PlayerCardKey key) {
  if (key.profileId != null && player.profileId == key.profileId) return true;
  if (key.fullName.isEmpty) return false;
  return _normalize(player.fullName) == _normalize(key.fullName) &&
      player.isGoalkeeper == key.isGoalkeeper;
}

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Adresse du classement d'une statistique, ouvert depuis la fiche de [key]
/// (dont la ligne sera mise en évidence).
String playerStatRankingLocation({
  required PlayerCardKey key,
  required PlayerStat stat,
  required StatisticsPeriod period,
}) {
  return Uri(
    path: '/stats/joueur/classement',
    queryParameters: {
      'stat': stat.slug,
      'periode': period.databaseKey,
      ...Uri.parse(playerCardLocation(key)).queryParameters,
    },
  ).toString();
}

StatisticsPeriod statisticsPeriodFromKey(String? key) {
  for (final period in StatisticsPeriod.values) {
    if (period.databaseKey == key) return period;
  }
  return StatisticsPeriod.current;
}

/// Une ligne du classement. [rank] est `null` pour un joueur qui n'a pas
/// assez de matchs pour être classé sur une moyenne.
class PlayerStatRankingEntry {
  const PlayerStatRankingEntry({required this.player, required this.rank});

  final PlayerStatistics player;
  final int? rank;

  bool get isRanked => rank != null;
}

/// Classement complet de [players] sur [stat].
///
/// Tout l'effectif de la période y figure, zéros compris, ex aequo au même
/// rang. Sur une moyenne, les joueurs sous [minMatches] matchs viennent
/// ensuite, sans rang. Le rang d'un joueur est celui qu'annonce sa fiche
/// (« 3e du club »).
List<PlayerStatRankingEntry> rankPlayersOnStat(
  List<PlayerStatistics> players,
  PlayerStat stat, {
  required int minMatches,
}) {
  bool eligible(PlayerStatistics p) =>
      !stat.isAverage || (p.matchesPlayed ?? 0) >= minMatches;

  int compare(PlayerStatistics a, PlayerStatistics b) {
    final byValue = stat.valueOf(b).compareTo(stat.valueOf(a));
    if (byValue != 0) return byValue;
    return a.playerName.toLowerCase().compareTo(b.playerName.toLowerCase());
  }

  final ranked = players.where(eligible).toList()..sort(compare);
  final unranked = players.where((p) => !eligible(p)).toList()..sort(compare);

  final entries = <PlayerStatRankingEntry>[];
  for (var i = 0; i < ranked.length; i++) {
    final value = stat.valueOf(ranked[i]);
    // Rang « competition » : deux ex aequo partagent le meilleur rang.
    final rank = i > 0 && stat.valueOf(ranked[i - 1]) == value
        ? entries[i - 1].rank
        : i + 1;
    entries.add(PlayerStatRankingEntry(player: ranked[i], rank: rank));
  }
  return [
    ...entries,
    for (final p in unranked) PlayerStatRankingEntry(player: p, rank: null),
  ];
}
