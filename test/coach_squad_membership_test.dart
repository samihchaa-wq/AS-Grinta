import 'package:as_grinta/features/sports_management/domain/match_availability_board.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Le coach entre dans l'effectif du match dès qu'il se dit présent, mais il
/// n'entre jamais dans la composition d'équipe. Le serveur refuse d'ailleurs
/// toute composition qui le contient : si l'écran le proposait, l'enregistrement
/// échouerait sans que l'administrateur comprenne pourquoi.
void main() {
  group('Le coach dans l’effectif', () {
    test('il est convoqué mais ne peut jamais être aligné', () {
      final coach = _convocationPlayer(
        participantId: 'coach',
        convoked: true,
        isCoach: true,
      );

      expect(coach.isConvoked, isTrue);
      expect(coach.canBeSelected, isFalse);
    });

    test('un joueur convoqué reste alignable', () {
      final player = _convocationPlayer(
        participantId: 'player',
        convoked: true,
        isCoach: false,
      );

      expect(player.canBeSelected, isTrue);
    });

    test('la composition ne reçoit pas le coach', () {
      final composition = MatchComposition.initial(
        convocations: _convocations([
          _convocationPlayer(
            participantId: 'player',
            convoked: true,
            isCoach: false,
          ),
          _convocationPlayer(
            participantId: 'coach',
            convoked: true,
            isCoach: true,
          ),
        ]),
        goalkeeperSeasonPlayerIds: const {},
      );

      expect(
        composition.entries.map((entry) => entry.participantId),
        ['player'],
        reason: 'le serveur attend exactement les joueurs de rotation',
      );
    });
  });

  group('Le coach dans le tableau des disponibilités', () {
    test('présent, il compte comme convoqué et jamais comme en attente', () {
      final coach = _boardPlayer(isCoach: true, convoked: true);

      expect(coach.isConvoked, isTrue);
      expect(coach.isWaitlisted, isFalse);
    });

    test('il n’est pas mis en liste d’attente, même sans convocation', () {
      final coach = _boardPlayer(isCoach: true, convoked: false);

      expect(coach.isWaitlisted, isFalse);
    });

    test('un joueur présent non convoqué reste en liste d’attente', () {
      final player = _boardPlayer(isCoach: false, convoked: false);

      expect(player.isWaitlisted, isTrue);
    });
  });

  test('l’attribut Coach se lit dans la charge utile du serveur', () {
    final parsed = ConvocationPlayer.fromJson(const {
      'participant_id': 'coach',
      'season_player_id': 'sp-coach',
      'first_name': 'Philippe',
      'last_name': 'Coach',
      'is_coach': true,
      'availability_status': 'available',
      'convocation_status': 'convoked',
    });

    expect(parsed.isCoach, isTrue);
    expect(parsed.canBeSelected, isFalse);
  });

  group('Le compteur d’une colonne d’effectif', () {
    test('compte le coach à part pour ne pas gonfler le nombre de joueurs', () {
      final players = [
        for (var index = 0; index < 12; index++)
          _convocationPlayer(
            participantId: 'joueur-$index',
            convoked: true,
            isCoach: false,
          ),
        _convocationPlayer(
          participantId: 'coach',
          convoked: true,
          isCoach: true,
        ),
      ];

      expect(effectifCountLabel(players), '12 + coach');
    });

    test('reste un simple total quand aucun coach n’est dans la colonne', () {
      final players = [
        _convocationPlayer(
          participantId: 'joueur',
          convoked: true,
          isCoach: false,
        ),
      ];

      expect(effectifCountLabel(players), '1');
      expect(effectifCountLabel(const []), '0');
    });

    test('accorde le pluriel au-delà d’un coach', () {
      final players = [
        _convocationPlayer(
          participantId: 'joueur',
          convoked: true,
          isCoach: false,
        ),
        _convocationPlayer(
          participantId: 'coach-1',
          convoked: true,
          isCoach: true,
        ),
        _convocationPlayer(
          participantId: 'coach-2',
          convoked: true,
          isCoach: true,
        ),
      ];

      expect(effectifCountLabel(players), '1 + 2 coachs');
    });
  });
}

ConvocationPlayer _convocationPlayer({
  required String participantId,
  required bool convoked,
  required bool isCoach,
}) {
  final status =
      convoked ? ConvocationStatus.convoked : ConvocationStatus.notConvoked;
  return ConvocationPlayer(
    participantId: participantId,
    seasonPlayerId: 'sp-$participantId',
    firstName: participantId,
    lastName: 'Test',
    isCoach: isCoach,
    availabilityStatus: 'available',
    convocationStatus: status,
    publishedConvocationStatus: status,
    manualOverride: false,
    waitlistPosition: null,
    recommendedNotConvoked: false,
    turnShouldConsume: false,
    turnState: WaitlistTurnState.notApplicable,
    promotedAfterWithdrawalAt: null,
  );
}

MatchConvocations _convocations(List<ConvocationPlayer> players) {
  return MatchConvocations(
    matchId: 'match-coach',
    opponentName: 'Coach FC',
    kickoffAt: DateTime(2099, 6, 20, 18),
    seasonId: 'season-coach',
    squadSizeLimit: 14,
    publishedSquadSizeLimit: 14,
    convocationState: 'published',
    convocationVersion: 1,
    hasUnpublishedChanges: false,
    lateWithdrawalCutoffAt: null,
    availableCount: 1,
    convokedCount: 1,
    notConvokedCount: 0,
    players: players,
  );
}

MatchAvailabilityBoardPlayer _boardPlayer({
  required bool isCoach,
  required bool convoked,
}) {
  return MatchAvailabilityBoardPlayer(
    participantId: isCoach ? 'coach' : 'player',
    firstName: isCoach ? 'Philippe' : 'Alice',
    lastName: 'Test',
    status: MatchAvailabilityBoardStatus.present,
    convocationStatus: convoked ? 'convoked' : 'not_convoked',
    isGuest: false,
    isCoach: isCoach,
  );
}
