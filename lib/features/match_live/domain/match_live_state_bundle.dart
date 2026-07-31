import 'package:as_grinta/features/match_live/domain/match_live_event.dart';
import 'package:as_grinta/features/match_live/domain/match_live_session.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';

/// Regroupe tout ce que renvoie get_match_live_state (et chaque RPC
/// d'écriture, qui renvoie la même forme) : le client interprète toujours un
/// seul bundle, quelle que soit l'action qui l'a produit.
class MatchLiveStateBundle {
  const MatchLiveStateBundle({
    required this.session,
    required this.lineup,
    required this.events,
    required this.substituteCounts,
  });

  factory MatchLiveStateBundle.fromRpc(Object? raw) {
    final json = _map(raw);
    final session = MatchLiveSession.fromJson(json);
    final lineup = MatchComposition.tryFromRpc(json['lineup']);
    final eventsRaw = json['events'];
    final countsRaw = json['substitute_counts'];
    return MatchLiveStateBundle(
      session: session,
      lineup: lineup,
      events: eventsRaw is List
          ? eventsRaw
              .map((row) => MatchLiveEvent.fromJson(_map(row)))
              .toList()
          : const [],
      substituteCounts: countsRaw is Map
          ? countsRaw.map(
              (key, value) =>
                  MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
            )
          : const {},
    );
  }

  final MatchLiveSession session;
  final MatchComposition? lineup;
  final List<MatchLiveEvent> events;

  /// participantId -> nombre de fois sur le banc (démarrer sur le banc
  /// compte 1 ; chaque sortie ultérieure vers le banc incrémente à nouveau).
  final Map<String, int> substituteCounts;

  List<MatchLiveEvent> get substitutions =>
      events.where((e) => e.type == MatchLiveEventType.substitution).toList();

  List<MatchLiveEvent> get ownGoals =>
      events.where((e) => e.type == MatchLiveEventType.goalUs).toList();

  int timesBenched(String participantId) => substituteCounts[participantId] ?? 0;
}

Map<String, dynamic> _map(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const {};
}
