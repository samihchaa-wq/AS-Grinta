import 'package:as_grinta/features/match_live/domain/match_live_event.dart';

/// Une salve de remplacements : les changements validés ensemble par le coach.
///
/// Le coach valide ses changements d'un seul geste, ils partagent donc la même
/// mi-temps et la même minute. C'est ce couple qui identifie une salve.
class SubstitutionSalvo {
  const SubstitutionSalvo({
    required this.half,
    required this.number,
    required this.colorIndex,
  });

  /// Mi-temps de la salve (1 ou 2).
  final int half;

  /// Numéro de la salve dans sa mi-temps : repart à 1 à la reprise.
  final int number;

  /// Rang de la salve sur tout le match, pour lui donner sa couleur.
  final int colorIndex;
}

/// Repère d'une sortie du terrain : « repos.rang ».
///
/// [rest] compte les repos du joueur qui sort, celui-ci compris. Commencer sur
/// le banc compte comme un premier repos : la première sortie d'un remplaçant
/// est donc déjà un 2.x. [rank] est l'ordre de cette sortie parmi toutes les
/// sorties du même tour (tous les 2.x, par exemple).
class SubstitutionExitMark {
  const SubstitutionExitMark({required this.rest, required this.rank});

  final int rest;
  final int rank;

  String get label => '$rest.$rank';
}

/// Remplacements dans l'ordre chronologique : mi-temps, puis minute, puis
/// ordre d'arrivée.
List<MatchLiveEvent> _chronologicalSubstitutions(
  Iterable<MatchLiveEvent> events,
) {
  final substitutions = events
      .where((event) => event.type == MatchLiveEventType.substitution)
      .toList();
  final indexed = [
    for (var i = 0; i < substitutions.length; i++) (i, substitutions[i]),
  ]..sort((a, b) {
      final byHalf = a.$2.half.compareTo(b.$2.half);
      if (byHalf != 0) return byHalf;
      final byMinute = a.$2.minute.compareTo(b.$2.minute);
      if (byMinute != 0) return byMinute;
      return a.$1.compareTo(b.$1);
    });
  return [for (final (_, event) in indexed) event];
}

/// Associe chaque remplacement au repère du joueur qui sort.
///
/// Un joueur qui entre sans être jamais sorti était sur le banc : il a déjà
/// eu un repos. Un joueur ajouté en cours de match est traité de la même façon.
Map<MatchLiveEvent, SubstitutionExitMark> substitutionExitMarksByEvent(
  Iterable<MatchLiveEvent> events,
) {
  final rests = <String, int>{};
  final ranksByRest = <int, int>{};
  final result = Map<MatchLiveEvent, SubstitutionExitMark>.identity();
  for (final event in _chronologicalSubstitutions(events)) {
    final outKey = event.playerOutParticipantId ??
        event.playerOutName ??
        'event:${event.id}';
    final rest = (rests[outKey] ?? 0) + 1;
    rests[outKey] = rest;
    final rank = (ranksByRest[rest] ?? 0) + 1;
    ranksByRest[rest] = rank;
    result[event] = SubstitutionExitMark(rest: rest, rank: rank);

    final inKey = event.playerInParticipantId ?? event.playerInName;
    if (inKey != null) rests.putIfAbsent(inKey, () => 1);
  }
  return result;
}

/// Associe chaque remplacement à sa salve. La table compare les événements
/// par identité : deux événements sans identifiant ne se confondent pas.
///
/// Les événements sont lus dans l'ordre chronologique.
Map<MatchLiveEvent, SubstitutionSalvo> substitutionSalvosByEvent(
  Iterable<MatchLiveEvent> events,
) {
  final result = Map<MatchLiveEvent, SubstitutionSalvo>.identity();
  SubstitutionSalvo? current;
  int? currentMinute;
  var colorIndex = -1;
  for (final event in _chronologicalSubstitutions(events)) {
    final sameSalvo = current != null &&
        current.half == event.half &&
        currentMinute == event.minute;
    if (!sameSalvo) {
      colorIndex += 1;
      final number = current != null && current.half == event.half
          ? current.number + 1
          : 1;
      current = SubstitutionSalvo(
        half: event.half,
        number: number,
        colorIndex: colorIndex,
      );
      currentMinute = event.minute;
    }
    result[event] = current;
  }
  return result;
}
