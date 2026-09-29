import 'package:as_grinta/features/match_live/domain/match_live_event.dart';
import 'package:as_grinta/features/match_live/domain/substitution_salvos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MatchLiveEvent sub(String id, int minute, int half) => MatchLiveEvent(
        id: id,
        type: MatchLiveEventType.substitution,
        minute: minute,
        half: half,
      );

  test('les changements validés ensemble forment une salve', () {
    final events = [
      sub('a', 5, 1),
      sub('b', 5, 1),
      const MatchLiveEvent(
        id: 'g',
        type: MatchLiveEventType.goalUs,
        minute: 8,
        half: 1,
      ),
      sub('c', 32, 1),
      sub('d', 46, 2),
      sub('e', 52, 2),
    ];
    final salvos = substitutionSalvosByEvent(events);

    expect(salvos[events[0]]!.label, '1.1');
    expect(identical(salvos[events[0]], salvos[events[1]]), isTrue);
    expect(salvos.containsKey(events[2]), isFalse);
    expect(salvos[events[3]]!.label, '1.2');
    expect(salvos[events[4]]!.label, '2.1');
    expect(salvos[events[5]]!.label, '2.2');
    expect(
      [
        for (final e in [events[0], events[3], events[4], events[5]])
          salvos[e]!.colorIndex
      ],
      [0, 1, 2, 3],
    );
  });
}
