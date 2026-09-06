import 'package:as_grinta/features/sports_management/domain/internal_match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/internal_team_formation.dart';
import 'package:flutter_test/flutter_test.dart';

InternalCompositionEntry fieldPlayer(
  String id, {
  required int teamNo,
  required String slot,
  double x = .5,
  double y = .5,
}) =>
    InternalCompositionEntry(
      participantId: id,
      displayName: 'Joueur $id',
      isGuest: false,
      isGoalkeeper: slot == 'GB',
      teamNo: teamNo,
      zone: 'field',
      x: x,
      y: y,
      slotLabel: slot,
    );

void main() {
  group('formations entre nous', () {
    test('un effectif supérieur à 11 utilise les formations à onze', () {
      final formations = internalFormationsForPlayerCount(14);

      expect(formations, isNotEmpty);
      expect(
        formations.every((formation) => formation.playerCount == 11),
        isTrue,
      );
      expect(
        internalFormationByCode(
          playerCount: 14,
          code: '4-2-3-1',
        )?.playerCount,
        11,
      );
    });

    test('zéro joueur ne propose aucune formation', () {
      expect(internalFormationsForPlayerCount(0), isEmpty);
    });
  });

  group('composition manuelle entre nous', () {
    test('13 joueurs exigent 11 titulaires et 2 joueurs sur le banc', () {
      final entries = <InternalCompositionEntry>[
        for (var i = 0; i < 11; i += 1)
          fieldPlayer(
            'a$i',
            teamNo: 1,
            slot: i == 0 ? 'GB' : 'S$i',
          ),
        for (var i = 11; i < 13; i += 1)
          InternalCompositionEntry(
            participantId: 'a$i',
            displayName: 'A$i',
            isGuest: false,
            isGoalkeeper: false,
            teamNo: 1,
            zone: 'bench',
            sortOrder: i - 11,
          ),
        fieldPlayer('b0', teamNo: 2, slot: 'GB'),
      ];

      final composition = InternalMatchComposition(
        matchId: 'm',
        team1Name: 'A',
        team2Name: 'B',
        team1FormationCode: '4-4-2',
        team2FormationCode: 'GB',
        entries: entries,
      );

      expect(composition.isVisualComplete, isTrue);
    });

    test('un joueur encore à placer empêche l’enregistrement visuel', () {
      final composition = InternalMatchComposition(
        matchId: 'm',
        team1Name: 'A',
        team2Name: 'B',
        team1FormationCode: '4-4-2',
        team2FormationCode: 'GB',
        entries: [
          const InternalCompositionEntry(
            participantId: 'a0',
            displayName: 'A0',
            isGuest: false,
            isGoalkeeper: true,
            teamNo: 1,
          ),
          fieldPlayer('b0', teamNo: 2, slot: 'GB'),
        ],
      );

      expect(composition.isVisualComplete, isFalse);
    });

    test('un titulaire sans coordonnées complètes est refusé', () {
      final composition = InternalMatchComposition(
        matchId: 'm',
        team1Name: 'A',
        team2Name: 'B',
        team1FormationCode: 'GB',
        team2FormationCode: 'GB',
        entries: [
          const InternalCompositionEntry(
            participantId: 'a0',
            displayName: 'A0',
            isGuest: false,
            isGoalkeeper: true,
            teamNo: 1,
            zone: 'field',
            slotLabel: 'GB',
          ),
          fieldPlayer('b0', teamNo: 2, slot: 'GB'),
        ],
      );

      expect(composition.isVisualComplete, isFalse);
    });

    test('un banc est interdit tant que l’équipe ne dépasse pas onze joueurs',
        () {
      final composition = InternalMatchComposition(
        matchId: 'm',
        team1Name: 'A',
        team2Name: 'B',
        team1FormationCode: 'GB',
        team2FormationCode: 'GB',
        entries: [
          const InternalCompositionEntry(
            participantId: 'a0',
            displayName: 'A0',
            isGuest: false,
            isGoalkeeper: true,
            teamNo: 1,
            zone: 'bench',
          ),
          fieldPlayer('b0', teamNo: 2, slot: 'GB'),
        ],
      );

      expect(composition.isVisualComplete, isFalse);
    });
  });
}
