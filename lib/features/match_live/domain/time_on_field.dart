import 'package:as_grinta/features/match_live/domain/match_live_event.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';

/// Minutes passées sur le terrain depuis la dernière entrée en jeu, par
/// joueur du terrain.
///
/// Un titulaire jamais sorti compte depuis le coup d'envoi. Un joueur entré
/// en cours de match compte depuis la minute de son entrée (la minute de jeu
/// affichée, comme dans le journal) : la valeur est donc arrondie à la
/// minute près. Le compteur suit le chrono : il s'arrête avec lui.
Map<String, int> minutesOnField({
  required Iterable<MatchCompositionEntry> field,
  required Iterable<MatchLiveEvent> events,
  required Duration elapsed,
}) {
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

  // Minute de jeu (base 0) de la dernière entrée de chaque joueur.
  final enteredAt = <String, int>{};
  for (final (_, event) in indexed) {
    final id = event.playerInParticipantId;
    if (id != null) enteredAt[id] = event.minute - 1;
  }

  final now = elapsed.inMinutes;
  return {
    for (final entry in field)
      entry.participantId:
          (now - (enteredAt[entry.participantId] ?? 0)).clamp(0, 1 << 20),
  };
}
