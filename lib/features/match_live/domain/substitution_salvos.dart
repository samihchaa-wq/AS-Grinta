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

  /// Libellé affiché à gauche des remplacements : « mi-temps.salve ».
  String get label => '$half.$number';
}

/// Associe chaque remplacement à sa salve. La table compare les événements
/// par identité : deux événements sans identifiant ne se confondent pas.
///
/// Les événements sont lus dans l'ordre chronologique : mi-temps, puis minute,
/// puis ordre d'arrivée.
Map<MatchLiveEvent, SubstitutionSalvo> substitutionSalvosByEvent(
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

  final result = Map<MatchLiveEvent, SubstitutionSalvo>.identity();
  SubstitutionSalvo? current;
  int? currentMinute;
  var colorIndex = -1;
  for (final (_, event) in indexed) {
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
