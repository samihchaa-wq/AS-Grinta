import 'package:as_grinta/features/match_live/domain/match_live_event.dart';
import 'package:as_grinta/features/match_live/domain/substitution_salvos.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:flutter/painting.dart';

/// Prénom d'un joueur qui sort à la prochaine salve.
const nextOutSureColor = Color(0xFFFF5A52);

/// Prénom d'un joueur à égalité pour les dernières places.
const nextOutToChooseColor = Color(0xFFFFB74D);

/// Prochains joueurs à sortir, à titre informatif pour le coach.
class NextOutPlayers {
  const NextOutPlayers({this.sure = const {}, this.toChoose = const {}});

  /// Sortent à la prochaine salve.
  final Set<String> sure;

  /// À égalité pour les dernières places : le coach choisit parmi eux.
  final Set<String> toChoose;

  static const none = NextOutPlayers();
}

/// Les prochains à sortir sont ceux qui se sont le moins reposés : autant que
/// de remplaçants sur le banc ([benchCount]), une salve remplaçant tout le
/// banc. À nombre de repos égal, le repos le plus ancien sort en premier.
/// C'est l'ordre du repère « passage.série » : un titulaire jamais sorti vaut
/// « 0.0 », un joueur entré du banc sans en être ressorti « 1.0 ». Le gardien
/// n'est jamais compté.
///
/// Quand plusieurs joueurs au même repère se disputent les dernières places,
/// ils sont proposés au choix, à condition d'être au plus [benchCount] : au
/// delà (par exemple les dix titulaires au coup d'envoi), l'indication
/// n'aiderait plus et ils ne sont pas signalés.
NextOutPlayers nextOutPlayers({
  required Iterable<MatchCompositionEntry> field,
  required Iterable<MatchLiveEvent> events,
  required Map<String, int> substituteCounts,
  required int benchCount,
}) {
  final outfield = field.where((entry) => !entry.isGoalkeeper).toList();
  if (benchCount <= 0 || outfield.isEmpty) return NextOutPlayers.none;

  final lastExits = lastExitMarksByParticipant(events);
  (int, int) markOf(String participantId) {
    final exit = lastExits[participantId];
    if (exit != null) return (exit.rest, exit.rank);
    return (substituteCounts[participantId] ?? 0, 0);
  }

  int compare((int, int) a, (int, int) b) {
    final byRest = a.$1.compareTo(b.$1);
    return byRest != 0 ? byRest : a.$2.compareTo(b.$2);
  }

  final ranked = [
    for (final entry in outfield)
      (entry.participantId, markOf(entry.participantId)),
  ]..sort((a, b) => compare(a.$2, b.$2));
  if (ranked.length <= benchCount) {
    return NextOutPlayers(sure: {for (final (id, _) in ranked) id});
  }

  final boundary = ranked[benchCount - 1].$2;
  final sure = {
    for (final (id, mark) in ranked)
      if (compare(mark, boundary) < 0) id,
  };
  final atBoundary = {
    for (final (id, mark) in ranked)
      if (compare(mark, boundary) == 0) id,
  };
  if (sure.length + atBoundary.length <= benchCount) {
    return NextOutPlayers(sure: {...sure, ...atBoundary});
  }
  return NextOutPlayers(
    sure: sure,
    toChoose: atBoundary.length <= benchCount ? atBoundary : const {},
  );
}
