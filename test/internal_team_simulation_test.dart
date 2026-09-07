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
    const expectedCodes = <int, String>{
      1: 'GB',
      2: '1',
      3: '1-1',
      4: '2-1',
      5: '1-2-1',
      6: '2-2-1',
      7: '2-3-1',
      8: '3-3-1',
      9: '3-3-2',
      10: '3-4-2',
      11: '4-3-3',
    };

    test('chaque effectif de 1 à 11 n’a qu’un seul dispositif', () {
      for (final entry in expectedCodes.entries) {
        final formations = internalFormationsForPlayerCount(entry.key);

        expect(formations, hasLength(1), reason: '${entry.key} joueurs');
        expect(formations.single.code, entry.value);
        expect(formations.single.playerCount, entry.key);
      }
    });

    test('au-delà de 11, le onze reste automatiquement en 4-3-3', () {
      final formation = internalDefaultFormationForPlayerCount(14);

      expect(formation?.code, '4-3-3');
      expect(formation?.playerCount, 11);
      expect(
        internalFormationByCode(playerCount: 14, code: '4-2-3-1'),
        isNull,
      );
    });

    test('le 3-3-2 garde trois lignes réalistes et deux pointes resserrées', () {
      final formation = internalDefaultFormationForPlayerCount(9)!;
      final slots = {for (final slot in formation.slots) slot.label: slot};

      expect(slots['BUG']!.position.dx, closeTo(.38, .001));
      expect(slots['BUD']!.position.dx, closeTo(.62, .001));
      expect(slots['BUG']!.position.dy, closeTo(.20, .001));
      expect(slots['DC']!.position.dy, greaterThan(slots['MC']!.position.dy));
      expect(slots['MC']!.position.dy, greaterThan(slots['BUG']!.position.dy));
    });

    test('tous les gabarits restent dans une zone visuelle sûre du terrain', () {
      for (final formation in internalDefaultFormations.values) {
        expect(
          formation.slots.map((slot) => slot.label).toSet(),
          hasLength(formation.slots.length),
        );
        for (final slot in formation.slots) {
          expect(slot.position.dx, inInclusiveRange(.12, .88));
          expect(slot.position.dy, inInclusiveRange(.16, .85));
        }
      }
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
        team1FormationCode: '4-3-3',
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
