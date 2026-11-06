import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/sport_match_finalization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('moving an entry preserves display metadata', () {
    const entry = MatchCompositionEntry(
      participantId: 'participant',
      seasonPlayerId: 'player',
      displayName: 'Samih',
      isGoalkeeper: false,
      zone: MatchCompositionZone.bench,
      photoUrl: 'https://example.test/photo.jpg',
      goals: 2,
      assists: 3,
      isMotm: true,
      sortOrder: 0,
      availabilityStatus: 'available',
      convocationStatus: 'convoked',
      selectionStatus: 'substitute',
    );

    final moved = entry.moveTo(MatchCompositionZone.field, x: .5, y: .8);

    expect(moved.photoUrl, entry.photoUrl);
    expect(moved.goals, 2);
    expect(moved.assists, 3);
    expect(moved.isMotm, isTrue);
  });

  test('copyWith keeps every display field it was not asked to change', () {
    const entry = MatchCompositionEntry(
      participantId: 'participant',
      seasonPlayerId: 'player',
      guestPlayerId: 'guest',
      displayName: 'Samih',
      lastInitial: 'C',
      isGuest: true,
      isGoalkeeper: true,
      zone: MatchCompositionZone.field,
      x: .4,
      y: .6,
      slotLabel: 'GB',
      photoUrl: 'players/samih.jpg',
      goals: 2,
      assists: 3,
      isMotm: true,
      isVacant: true,
      sortOrder: 7,
      availabilityStatus: 'absent',
      convocationStatus: 'convoked',
      selectionStatus: 'starter',
    );

    final copy = entry.copyWith(sortOrder: 9);

    expect(copy.sortOrder, 9);
    expect(copy.participantId, entry.participantId);
    expect(copy.seasonPlayerId, entry.seasonPlayerId);
    expect(copy.guestPlayerId, entry.guestPlayerId);
    expect(copy.displayName, entry.displayName);
    expect(copy.lastInitial, entry.lastInitial);
    expect(copy.isGuest, entry.isGuest);
    expect(copy.isGoalkeeper, entry.isGoalkeeper);
    expect(copy.zone, entry.zone);
    expect(copy.x, entry.x);
    expect(copy.y, entry.y);
    expect(copy.slotLabel, entry.slotLabel);
    expect(copy.photoUrl, entry.photoUrl);
    expect(copy.goals, entry.goals);
    expect(copy.assists, entry.assists);
    expect(copy.isMotm, entry.isMotm);
    expect(copy.isVacant, entry.isVacant);
    expect(copy.availabilityStatus, entry.availabilityStatus);
    expect(copy.convocationStatus, entry.convocationStatus);
    expect(copy.selectionStatus, entry.selectionStatus);
  });

  test('post-match initialization selects only actual present players', () {
    final finalization = SportMatchFinalization(
      matchId: 'match',
      opponentName: 'Adversaire',
      isHome: true,
      kickoffAt: DateTime(2026),
      matchStatus: 'termine',
      isValidated: true,
      version: 1,
      scoreAsGrinta: 2,
      scoreAdverse: 1,
      compositionVersion: 0,
      presenceState: 'confirmed',
      voteState: 'draft',
      participants: const [
        SportFinalParticipant(
          participantId: 'present',
          seasonPlayerId: 'player-present',
          displayName: 'Présent',
          isGuest: false,
          isGoalkeeper: true,
          plannedZone: 'available',
          present: true,
          selectionStatus: SportFinalSelectionStatus.substitute,
          goals: 1,
          assists: 2,
          cleanSheet: false,
          photoUrl: 'https://example.test/present.jpg',
          isMotm: true,
        ),
        SportFinalParticipant(
          participantId: 'absent',
          seasonPlayerId: 'player-absent',
          displayName: 'Absent',
          isGuest: false,
          isGoalkeeper: false,
          plannedZone: 'field',
          present: false,
          selectionStatus: SportFinalSelectionStatus.notSelected,
          goals: 0,
          assists: 0,
          cleanSheet: false,
        ),
      ],
    );

    final composition = MatchComposition.initialFromFinalization(
      finalization: finalization,
    );

    final present = composition.entries.singleWhere(
      (entry) => entry.participantId == 'present',
    );
    final absent = composition.entries.singleWhere(
      (entry) => entry.participantId == 'absent',
    );
    expect(present.zone, MatchCompositionZone.bench);
    expect(present.photoUrl, isNotNull);
    expect(present.goals, 1);
    expect(present.assists, 2);
    expect(present.isMotm, isTrue);
    expect(absent.zone, MatchCompositionZone.notSelected);
  });
}
