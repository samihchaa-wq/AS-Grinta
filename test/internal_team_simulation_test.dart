import 'dart:math';

import 'package:as_grinta/features/sports_management/domain/internal_match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/internal_team_formation.dart';
import 'package:as_grinta/features/sports_management/domain/internal_team_simulation.dart';
import 'package:flutter_test/flutter_test.dart';

InternalCompositionEntry player(
  String id, {
  bool goalkeeper = false,
}) =>
    InternalCompositionEntry(
      participantId: id,
      displayName: 'Joueur $id',
      isGuest: false,
      isGoalkeeper: goalkeeper,
    );

void main() {
  group('formations entre nous', () {
    test('un effectif supérieur à 11 utilise les formations à onze', () {
      final formations = internalFormationsForPlayerCount(14);

      expect(formations, isNotEmpty);
      expect(
          formations.every((formation) => formation.playerCount == 11), isTrue);
      expect(
        internalFormationByCode(playerCount: 14, code: '4-2-3-1')?.playerCount,
        11,
      );
    });

    test('zéro joueur ne propose aucune formation', () {
      expect(internalFormationsForPlayerCount(0), isEmpty);
    });
  });

  group('simulation entre nous', () {
    test('13 joueurs donnent 11 titulaires et 2 remplaçants', () {
      final players = [
        for (var i = 0; i < 13; i += 1)
          player('p${i.toString().padLeft(2, '0')}', goalkeeper: i == 0),
      ];
      final formation =
          internalFormationByCode(playerCount: players.length, code: '4-4-2')!;

      final result = simulateInternalTeam(
        formation: formation,
        players: players,
        profiles: const {},
        random: Random(1),
      );

      expect(result.slotByParticipantId.length, 11);
      expect(result.benchParticipantIds.length, 2);
      expect(
        {
          ...result.slotByParticipantId.keys,
          ...result.benchParticipantIds,
        }.length,
        13,
      );
      expect(result.slotByParticipantId['p00'], 'GB');
      expect(result.usedRandomGoalkeeper, isFalse);
    });

    test('sans gardien déclaré le gardien est tiré via le Random injecté', () {
      final players = [
        for (var i = 0; i < 7; i += 1) player('p$i'),
      ];
      final formation =
          internalFormationByCode(playerCount: players.length, code: '2-3-1')!;

      final first = simulateInternalTeam(
        formation: formation,
        players: players,
        profiles: const {},
        random: Random(42),
      );
      final second = simulateInternalTeam(
        formation: formation,
        players: players,
        profiles: const {},
        random: Random(42),
      );

      expect(first.usedRandomGoalkeeper, isTrue);
      expect(first.goalkeeperParticipantId, second.goalkeeperParticipantId);
      expect(
        first.slotByParticipantId[first.goalkeeperParticipantId],
        'GB',
      );
    });
  });

  test('la complétude accepte un banc seulement au-delà de onze', () {
    final entries = [
      for (var i = 0; i < 13; i += 1)
        InternalCompositionEntry(
          participantId: 'a$i',
          displayName: 'A$i',
          isGuest: false,
          isGoalkeeper: i == 0,
          teamNo: 1,
          slotLabel: i < 11 ? 'S$i' : null,
        ),
      InternalCompositionEntry(
        participantId: 'b0',
        displayName: 'B0',
        isGuest: false,
        isGoalkeeper: true,
        teamNo: 2,
        slotLabel: 'GB',
      ),
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
}
