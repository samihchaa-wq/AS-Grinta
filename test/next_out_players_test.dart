import 'package:as_grinta/features/match_live/domain/next_out_players.dart';
import 'package:as_grinta/features/match_live/domain/match_live_event.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:flutter_test/flutter_test.dart';

MatchCompositionEntry player(String id, {bool goalkeeper = false}) =>
    MatchCompositionEntry(
      participantId: id,
      seasonPlayerId: id,
      displayName: id,
      isGoalkeeper: goalkeeper,
      zone: MatchCompositionZone.field,
      sortOrder: 0,
      availabilityStatus: 'available',
      convocationStatus: 'convoked',
      selectionStatus: 'starter',
    );

var _serial = 0;
MatchLiveEvent change(String inP, String outP, int minute) => MatchLiveEvent(
      id: 'e${_serial++}',
      type: MatchLiveEventType.substitution,
      minute: minute,
      half: 1,
      playerInParticipantId: inP,
      playerOutParticipantId: outP,
      createdAt: DateTime.utc(2026, 9, 28, 19, minute),
    );

void main() {
  final starters = [for (var i = 1; i <= 10; i++) 'T$i'];

  test('coup d\'envoi : 10 titulaires à égalité pour 3 places, personne', () {
    final result = nextOutPlayers(
      field: [
        player('G', goalkeeper: true),
        for (final t in starters) player(t),
      ],
      events: const [],
      substituteCounts: const {},
      benchCount: 3,
    );
    expect(result.sure, isEmpty);
    expect(result.toChoose, isEmpty);
  });

  test('coupure nette : les 3 plus petits repères sortent', () {
    final result = nextOutPlayers(
      field: [
        player('G', goalkeeper: true),
        for (final id in ['A', 'B', 'C', 'D', 'E', 'F']) player(id),
      ],
      events: [
        change('Y1', 'B', 1),
        change('Y2', 'C', 1),
        change('Y3', 'D', 1),
        change('Y4', 'A', 2),
        change('Y5', 'E', 3),
        change('Y6', 'F', 3),
        change('E', 'Y5', 4),
        change('F', 'Y6', 4),
        change('Z1', 'E', 5),
        change('Z2', 'F', 5),
        change('E', 'Z1', 6),
        change('F', 'Z2', 6),
      ],
      substituteCounts: const {'A': 1, 'B': 1, 'C': 1, 'D': 1, 'E': 2, 'F': 2},
      benchCount: 3,
    );
    // Repères : B, C, D sortis ensemble à la 1re (1.1), A à la 2e (1.2),
    // E et F deux fois. A est derrière B, C, D : ce sont eux les 3 à sortir.
    expect(result.sure, {'B', 'C', 'D'});
    expect(result.toChoose, isEmpty);
  });

  test('égalité sur la dernière place : sûrs en rouge, candidats au choix', () {
    final result = nextOutPlayers(
      field: [
        player('G', goalkeeper: true),
        for (final id in ['S', 'U1', 'U2', 'U3', 'V1', 'V2']) player(id),
      ],
      events: [
        change('U1', 'W1', 1),
        change('U2', 'W2', 1),
        change('U3', 'W3', 1),
        change('W1', 'V1', 2),
        change('W2', 'V2', 2),
        change('V1', 'W1', 3),
        change('V2', 'W2', 3),
      ],
      substituteCounts: const {
        'U1': 1, 'U2': 1, 'U3': 1, 'V1': 1, 'V2': 1, 'W1': 2, 'W2': 2, //
      },
      benchCount: 3,
    );
    // S jamais sorti (0.0) ; U1..U3 entrés du banc (1.0) ; V1, V2 à 1.1.
    expect(result.sure, {'S'});
    expect(result.toChoose, {'U1', 'U2', 'U3'});
  });

  test('le gardien n\'est jamais signalé', () {
    final result = nextOutPlayers(
      field: [player('G', goalkeeper: true), player('A'), player('B')],
      events: [change('A', 'X', 5)],
      substituteCounts: const {'X': 1, 'A': 1},
      benchCount: 1,
    );
    expect(result.sure, {'B'});
  });
}
