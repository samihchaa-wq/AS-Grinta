import 'dart:math' as math;

import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_profiles.dart';
import 'package:flutter/painting.dart' show Offset;

/// Date à partir de laquelle les compositions enregistrées dans
/// l'application alimentent les postes de référence.
///
/// L'archive du club couvre les compositions jusqu'au 21 mai 2026 : reprendre
/// ces matchs depuis la base les compterait deux fois. Le raccord est posé un
/// peu plus tard, à la mise en service de la simulation, parce que les seules
/// compositions enregistrées entre les deux sont des matchs de test.
final DateTime kLivePositionHistoryStart = DateTime.utc(2026, 8, 8);

/// Un poste tenu par un joueur sur un match déjà joué.
class PlayedPosition {
  const PlayedPosition({
    required this.playerId,
    required this.position,
    required this.kickoffAt,
  });

  /// Identité canonique du joueur (`players.id`).
  final String playerId;

  /// Sa position sur le terrain, normalisée comme la feuille de match.
  final Offset position;

  final DateTime kickoffAt;

  /// La saison du match : une saison commence en juillet.
  int get season => kickoffAt.month >= 7 ? kickoffAt.year : kickoffAt.year - 1;

  /// Le poste le plus proche de l'endroit où le joueur a été aligné.
  String get slotLabel => nearestMatchSheetSlotLabel(position);

  /// Le poids de ce match dans le profil du joueur.
  ///
  /// Même formule et même ancrage que le fichier généré : les deux sources
  /// s'additionnent donc directement. Un match postérieur à la saison de
  /// référence pèse plus qu'un match de l'archive, ce qui est exactement le
  /// but — un joueur qui change de poste voit son profil suivre.
  double get weight => math
      .pow(
        .5,
        (kPositionProfilesReferenceSeason - season) /
            kPositionProfilesHalfLifeSeasons,
      )
      .toDouble();
}

/// Un poste représentant moins de 4 % du temps d'un joueur est du bruit.
const double _minShare = .04;

/// Au-delà de six postes, la queue de distribution n'apporte plus rien.
const int _maxSlotsPerPlayer = 6;

/// Les postes de référence, archive et matchs joués depuis réunis.
///
/// L'archive sert de socle et les compositions enregistrées dans
/// l'application viennent s'y ajouter, avec le poids de leur saison. Un
/// joueur absent de l'archive se construit un profil à partir de ses seuls
/// matchs ; un joueur qui change durablement de poste voit le sien glisser.
Map<String, PlayerPositionProfile> mergePlayerPositionProfiles({
  required List<PlayedPosition> history,
  Map<String, PlayerPositionProfile> archive = kPlayerPositionProfiles,
}) {
  if (history.isEmpty) return archive;

  final weights = <String, Map<String, double>>{};
  final played = <String, int>{};
  for (final entry in history) {
    (weights[entry.playerId] ??= <String, double>{}).update(
      entry.slotLabel,
      (current) => current + entry.weight,
      ifAbsent: () => entry.weight,
    );
    played.update(entry.playerId, (count) => count + 1, ifAbsent: () => 1);
  }

  final merged = <String, PlayerPositionProfile>{...archive};
  for (final playerId in weights.keys) {
    final base = archive[playerId];
    final added = weights[playerId]!;
    final combined = <String, double>{
      for (final sample in base?.samples ?? const <PlayerPositionSample>[])
        sample.slotLabel: sample.weight,
    };
    for (final slot in added.entries) {
      combined.update(
        slot.key,
        (current) => current + slot.value,
        ifAbsent: () => slot.value,
      );
    }

    // Le total englobe la queue de distribution que l'archive n'a pas
    // détaillée : la retirer du dénominateur gonflerait le poste principal et
    // ferait passer un polyvalent pour un joueur au poste marqué.
    final total = (base?.totalWeight ?? 0) +
        added.values.fold<double>(0, (sum, weight) => sum + weight);
    final samples = _rank(combined, total);
    if (samples.isEmpty) continue;
    merged[playerId] = PlayerPositionProfile(
      displayName: base?.displayName ?? '',
      appearances: (base?.appearances ?? 0) + played[playerId]!,
      totalWeight: total,
      samples: samples,
    );
  }
  return merged;
}

/// Trie les postes par poids décroissant et coupe la queue négligeable.
List<PlayerPositionSample> _rank(Map<String, double> weights, double total) {
  if (total <= 0) return const [];
  final ordered = weights.entries.toList()
    ..sort((a, b) {
      final byWeight = b.value.compareTo(a.value);
      return byWeight != 0 ? byWeight : a.key.compareTo(b.key);
    });
  return [
    for (final entry in ordered.take(_maxSlotsPerPlayer))
      if (entry.value / total >= _minShare)
        PlayerPositionSample(entry.key, entry.value),
  ];
}
