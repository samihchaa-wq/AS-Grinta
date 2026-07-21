import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a published composition snapshot', () {
    final composition = MatchComposition.tryFromRpc({
      'match_id': 'match-1',
      'formation_code': '4-3-3',
      'status': 'published',
      'version': 2,
      'has_unpublished_changes': false,
      'squad_size_exception_approved': false,
      'published_at': '2026-07-20T16:00:00Z',
      'entries': [
        {
          'participant_id': 'participant-1',
          'season_player_id': 'player-1',
          'display_name': 'Alex Gardien',
          'is_goalkeeper': true,
          'zone': 'field',
          'x': 0.5,
          'y': 0.9,
          'slot_label': 'GK',
          'sort_order': 0,
          'availability_status': 'available',
          'convocation_status': 'convoked',
          'selection_status': 'starter',
        },
        {
          'participant_id': 'participant-2',
          'season_player_id': 'player-2',
          'display_name': 'Sam Banc',
          'is_goalkeeper': false,
          'zone': 'bench',
          'sort_order': 0,
          'availability_status': 'available',
          'convocation_status': 'convoked',
          'selection_status': 'substitute',
        },
      ],
    });

    expect(composition, isNotNull);
    expect(composition!.version, 2);
    expect(composition.fieldCount, 1);
    expect(composition.benchCount, 1);
    expect(composition.hasGoalkeeperWarning, isFalse);
    expect(composition.publicationLabel, 'Publié · version 2');
    expect(
      composition.entriesFor(MatchCompositionZone.field).single.toRpcJson(),
      containsPair('x', 0.5),
    );
  });

  test('creates a complete initial draft from convocations', () {
    final convocations = MatchConvocations(
      matchId: 'match-1',
      opponentName: 'Test FC',
      kickoffAt: DateTime.utc(2026, 7, 26, 18),
      seasonId: 'season-1',
      squadSizeLimit: 14,
      convocationState: 'published',
      convocationVersion: 1,
      lateWithdrawalCutoffAt: null,
      availableCount: 1,
      convokedCount: 1,
      notConvokedCount: 0,
      players: const [
        ConvocationPlayer(
          participantId: 'participant-1',
          seasonPlayerId: 'player-1',
          firstName: 'Alex',
          lastName: 'Gardien',
          availabilityStatus: 'available',
          convocationStatus: ConvocationStatus.convoked,
          manualOverride: false,
          waitlistPosition: 1,
          recommendedNotConvoked: false,
          turnShouldConsume: false,
          turnState: WaitlistTurnState.notApplicable,
          promotedAfterWithdrawalAt: null,
        ),
        ConvocationPlayer(
          participantId: 'participant-2',
          seasonPlayerId: 'player-2',
          firstName: 'Sam',
          lastName: 'Absent',
          availabilityStatus: 'absent',
          convocationStatus: ConvocationStatus.notApplicable,
          manualOverride: false,
          waitlistPosition: 2,
          recommendedNotConvoked: false,
          turnShouldConsume: false,
          turnState: WaitlistTurnState.notApplicable,
          promotedAfterWithdrawalAt: null,
        ),
      ],
    );

    final composition = MatchComposition.initial(
      convocations: convocations,
      goalkeeperSeasonPlayerIds: const {'player-1'},
    );

    expect(composition.entries.length, 2);
    expect(composition.availableCount, 1);
    expect(composition.notSelectedCount, 1);
    expect(
      composition
          .entriesFor(MatchCompositionZone.available)
          .single
          .isGoalkeeper,
      isTrue,
    );
  });

  test('clears field coordinates when a player moves to the bench', () {
    const entry = MatchCompositionEntry(
      participantId: 'participant-1',
      seasonPlayerId: 'player-1',
      displayName: 'Alex',
      isGoalkeeper: false,
      zone: MatchCompositionZone.field,
      x: 0.3,
      y: 0.4,
      sortOrder: 0,
      availabilityStatus: 'available',
      convocationStatus: 'convoked',
      selectionStatus: 'starter',
    );

    final moved = entry.moveTo(MatchCompositionZone.bench);
    expect(moved.x, isNull);
    expect(moved.y, isNull);
    expect(moved.selectionStatus, 'substitute');
    expect(moved.toRpcJson()['zone'], 'bench');
  });

  test('treats a convoked guest as selectable without availability', () {
    final convocations = MatchConvocations(
      matchId: 'match-guest',
      opponentName: 'Invités FC',
      kickoffAt: DateTime.utc(2026, 7, 26, 18),
      seasonId: 'season-1',
      squadSizeLimit: 14,
      convocationState: 'draft',
      convocationVersion: 0,
      lateWithdrawalCutoffAt: null,
      availableCount: 1,
      convokedCount: 1,
      notConvokedCount: 0,
      players: const [
        ConvocationPlayer(
          participantId: 'participant-guest',
          seasonPlayerId: '',
          guestPlayerId: 'guest-1',
          firstName: 'Alex',
          lastName: 'Gardien',
          isGuest: true,
          isGoalkeeper: true,
          availabilityStatus: 'not_applicable',
          convocationStatus: ConvocationStatus.convoked,
          manualOverride: true,
          waitlistPosition: null,
          recommendedNotConvoked: false,
          turnShouldConsume: false,
          turnState: WaitlistTurnState.notApplicable,
          promotedAfterWithdrawalAt: null,
        ),
      ],
    );

    final composition = MatchComposition.initial(
      convocations: convocations,
      goalkeeperSeasonPlayerIds: const {},
    );
    final guest = composition.entriesFor(MatchCompositionZone.available).single;

    expect(guest.isGuest, isTrue);
    expect(guest.guestPlayerId, 'guest-1');
    expect(guest.displayName, 'Alex');
    expect(guest.canBeSelected, isTrue);
    expect(guest.isGoalkeeper, isTrue);

    final starter = guest.moveTo(MatchCompositionZone.field, x: 0.5, y: 0.1);
    final withGuestKeeper = composition.copyWith(entries: [starter]);
    expect(withGuestKeeper.hasGoalkeeperWarning, isFalse);
  });
}
