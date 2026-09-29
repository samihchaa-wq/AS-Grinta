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

    expect((salvos[events[0]]!.half, salvos[events[0]]!.number), (1, 1));
    expect(identical(salvos[events[0]], salvos[events[1]]), isTrue);
    expect(salvos.containsKey(events[2]), isFalse);
    expect((salvos[events[3]]!.half, salvos[events[3]]!.number), (1, 2));
    expect((salvos[events[4]]!.half, salvos[events[4]]!.number), (2, 1));
    expect((salvos[events[5]]!.half, salvos[events[5]]!.number), (2, 2));
    expect(
      [
        for (final e in [events[0], events[3], events[4], events[5]])
          salvos[e]!.colorIndex
      ],
      [0, 1, 2, 3],
    );
  });

  test('11 titulaires et 3 remplaçants, changements par trois', () {
    final starters = [for (var i = 1; i <= 11; i++) 'T$i'];
    final bench = ['R1', 'R2', 'R3'];
    // Sur le terrain, dans l'ordre où ils sortiront.
    final queue = [...starters];
    final waiting = [...bench];
    final events = <MatchLiveEvent>[];
    for (var salvo = 0; salvo < 6; salvo++) {
      for (var k = 0; k < 3; k++) {
        final out = queue.removeAt(0);
        final inPlayer = waiting.removeAt(0);
        events.add(
          MatchLiveEvent(
            id: 'e${events.length}',
            type: MatchLiveEventType.substitution,
            minute: 5 + salvo * 5,
            half: 1,
            playerInParticipantId: inPlayer,
            playerOutParticipantId: out,
          ),
        );
        queue.add(inPlayer);
        waiting.add(out);
      }
    }
    final marks = substitutionExitMarksByEvent(events);

    // Les joueurs sortis ensemble partagent le numéro de leur série.
    expect(
      [for (final e in events) marks[e]!.label],
      [
        '1.1', '1.1', '1.1', //
        '1.2', '1.2', '1.2', //
        '1.3', '1.3', '1.3', //
        '1.4', '1.4', '2.1', // R1 : entré au départ du banc
        '2.2', '2.2', '2.2', //
        '2.3', '2.3', '2.3', //
      ],
    );
    expect(events[11].playerOutParticipantId, 'R1');

    final lastExits = lastExitMarksByParticipant(events);
    expect(lastExits['T1']!.label, '2.2');
    expect(lastExits['T10']!.label, '1.4');
    expect(lastExits.containsKey('T5'), isTrue);
  });

  test('un joueur sorti hors de son tour garde son propre compteur', () {
    MatchLiveEvent sub(String id, int minute, String inId, String outId) =>
        MatchLiveEvent(
          id: id,
          type: MatchLiveEventType.substitution,
          minute: minute,
          half: 1,
          playerInParticipantId: inId,
          playerOutParticipantId: outId,
        );
    final events = [
      sub('a', 5, 'R1', 'T1'),
      sub('b', 10, 'T1', 'T2'),
      // T1 ressort avant que T3 ne soit jamais sorti.
      sub('c', 15, 'T2', 'T1'),
      sub('d', 20, 'T1', 'T3'),
    ];
    final marks = substitutionExitMarksByEvent(events);

    expect(
      [for (final e in events) marks[e]!.label],
      ['1.1', '1.2', '2.1', '1.3'],
    );
  });
}
