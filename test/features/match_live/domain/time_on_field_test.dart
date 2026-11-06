import 'package:as_grinta/features/match_live/domain/match_live_event.dart';
import 'package:as_grinta/features/match_live/domain/time_on_field.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:flutter_test/flutter_test.dart';

MatchCompositionEntry player(String id) => MatchCompositionEntry(
      participantId: id,
      seasonPlayerId: id,
      displayName: id,
      isGoalkeeper: false,
      zone: MatchCompositionZone.field,
      sortOrder: 0,
      availabilityStatus: 'available',
      convocationStatus: 'convoked',
      selectionStatus: 'starter',
    );

MatchLiveEvent change(String inP, String outP, int minute, {int half = 1}) =>
    MatchLiveEvent(
      id: '$inP-$minute',
      type: MatchLiveEventType.substitution,
      minute: minute,
      half: half,
      playerInParticipantId: inP,
      playerOutParticipantId: outP,
    );

void main() {
  test('titulaire : depuis le coup d\'envoi ; entrant : depuis son entrée', () {
    final minutes = minutesOnField(
      field: [player('T1'), player('R1')],
      events: [change('R1', 'T2', 21)], // entré à la 21e (20:xx)
      elapsed: const Duration(minutes: 32, seconds: 40),
    );
    expect(minutes, {'T1': 32, 'R1': 12});
  });

  test('un joueur ressorti puis revenu compte depuis son dernier retour', () {
    final minutes = minutesOnField(
      field: [player('A')],
      events: [
        change('X', 'A', 10),
        change('A', 'X', 30),
      ],
      elapsed: const Duration(minutes: 41),
    );
    expect(minutes, {'A': 12});
  });

  test('jamais négatif', () {
    final minutes = minutesOnField(
      field: [player('R1')],
      events: [change('R1', 'T1', 1)],
      elapsed: Duration.zero,
    );
    expect(minutes, {'R1': 0});
  });
}
