import 'package:as_grinta/features/match_live/domain/match_live_event.dart';

/// Une salve de remplacements : les changements validés ensemble par le coach.
///
/// Le coach valide ses changements d'un seul geste : le serveur les écrit
/// ensemble, avec la même heure d'enregistrement. C'est elle qui identifie une
/// salve, si bien que deux validations faites dans la même minute (chrono figé
/// à la mi-temps, par exemple) restent deux salves. Sans cette heure, la
/// mi-temps et la minute servent de repli.
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

/// Repère d'une sortie du terrain : « passage.série ».
///
/// [rest] compte les passages sur le banc du joueur qui sort, celui-ci
/// compris. Commencer sur le banc compte comme un premier passage : la
/// première sortie d'un remplaçant est donc déjà un 2.x. [rank] est le numéro
/// de la série parmi celles qui envoient des joueurs à ce même passage : les
/// joueurs sortis ensemble partagent le même repère.
class SubstitutionExitMark {
  const SubstitutionExitMark({required this.rest, required this.rank});

  final int rest;
  final int rank;

  String get label => '$rest.$rank';
}

/// Identifiant de la salve d'un remplacement : même validation, même salve.
(int, int, DateTime?) _salvoKey(MatchLiveEvent event) =>
    (event.half, event.minute, event.createdAt);

/// Remplacements dans l'ordre chronologique : mi-temps, puis minute, puis
/// heure d'enregistrement, puis ordre d'arrivée.
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
      final aAt = a.$2.createdAt;
      final bAt = b.$2.createdAt;
      if (aAt != null && bAt != null) {
        final byTime = aAt.compareTo(bAt);
        if (byTime != 0) return byTime;
      }
      return a.$1.compareTo(b.$1);
    });
  return [for (final (_, event) in indexed) event];
}

/// Associe chaque remplacement au repère du joueur qui sort.
///
/// Un joueur qui entre sans être jamais sorti était sur le banc : il a déjà
/// eu un passage. Un joueur ajouté en cours de match est traité de la même
/// façon. Une série regroupe les changements validés ensemble, comme une
/// salve.
Map<MatchLiveEvent, SubstitutionExitMark> substitutionExitMarksByEvent(
  Iterable<MatchLiveEvent> events,
) {
  final rests = <String, int>{};
  // Pour chaque passage : nombre de séries déjà vues, et la dernière.
  final seriesByRest = <int, int>{};
  final lastSeriesByRest = <int, (int, int, DateTime?)>{};
  final result = Map<MatchLiveEvent, SubstitutionExitMark>.identity();
  for (final event in _chronologicalSubstitutions(events)) {
    final outKey = event.playerOutParticipantId ??
        event.playerOutName ??
        'event:${event.id}';
    final rest = (rests[outKey] ?? 0) + 1;
    rests[outKey] = rest;
    final series = _salvoKey(event);
    if (lastSeriesByRest[rest] != series) {
      lastSeriesByRest[rest] = series;
      seriesByRest[rest] = (seriesByRest[rest] ?? 0) + 1;
    }
    result[event] = SubstitutionExitMark(rest: rest, rank: seriesByRest[rest]!);

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
  (int, int, DateTime?)? currentKey;
  var colorIndex = -1;
  for (final event in _chronologicalSubstitutions(events)) {
    final key = _salvoKey(event);
    final sameSalvo = current != null && currentKey == key;
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
      currentKey = key;
    }
    result[event] = current;
  }
  return result;
}

/// Repère de la dernière sortie de chaque joueur, par identifiant.
Map<String, SubstitutionExitMark> lastExitMarksByParticipant(
  Iterable<MatchLiveEvent> events,
) {
  final marks = substitutionExitMarksByEvent(events);
  return {
    for (final event in _chronologicalSubstitutions(events))
      if (event.playerOutParticipantId != null)
        event.playerOutParticipantId!: marks[event]!,
  };
}
