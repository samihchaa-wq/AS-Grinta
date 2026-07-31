import 'package:as_grinta/features/match_live/domain/match_live_event.dart';

/// Chronologie figée d'un match exporté, pour l'onglet "Faits du match".
/// `null` (voir [MatchLiveTimeline.tryFromRpc]) signifie que ce match n'a
/// jamais été suivi en direct : l'appelant doit alors ne rien afficher.
class MatchLiveTimeline {
  const MatchLiveTimeline({required this.matchId, required this.events});

  static MatchLiveTimeline? tryFromRpc(Object? raw) {
    if (raw == null) return null;
    final json = _map(raw);
    if (json.isEmpty || json['match_id'] == null) return null;
    final eventsRaw = json['events'];
    return MatchLiveTimeline(
      matchId: json['match_id'].toString(),
      events: eventsRaw is List
          ? eventsRaw
              .map((row) => MatchLiveEvent.fromJson(_map(row)))
              .toList()
          : const [],
    );
  }

  final String matchId;
  final List<MatchLiveEvent> events;

  List<MatchLiveEvent> eventsForHalf(int half) =>
      events.where((e) => e.half == half).toList();

  bool get hasSecondHalf => events.any((e) => e.half == 2);
}

Map<String, dynamic> _map(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const {};
}
