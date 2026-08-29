import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/match_squad_editing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Règles de l'onglet « Effectif », partagées avec le check d'avant coup
/// d'envoi : terrain = titulaires, banc = remplaçants, retiré = hors compte
/// rendu.
void main() {
  MatchCompositionEntry entry(
    String id, {
    MatchCompositionZone zone = MatchCompositionZone.bench,
    double? x,
    double? y,
    bool goalkeeper = false,
    int sortOrder = 0,
  }) {
    return MatchCompositionEntry(
      participantId: id,
      seasonPlayerId: 'season-$id',
      displayName: 'Joueur $id',
      isGoalkeeper: goalkeeper,
      zone: zone,
      x: x,
      y: y,
      sortOrder: sortOrder,
      availabilityStatus: 'available',
      convocationStatus: 'convoked',
      selectionStatus: 'substitute',
    );
  }

  MatchComposition lineupOf(
    List<MatchCompositionEntry> entries, {
    String? formationCode,
  }) {
    return MatchComposition(
      matchId: 'match-1',
      formationCode: formationCode,
      status: 'draft',
      version: 0,
      hasUnpublishedChanges: true,
      squadSizeExceptionApproved: false,
      entries: entries,
    );
  }

  final formation = formationForCode('4-4-2');

  group('terrain et banc', () {
    test('déposer un remplaçant sur un poste le rend titulaire', () {
      final lineup = lineupOf([entry('a'), entry('b')]);

      final next =
          placeEntryOnSlot(lineup, lineup.entries.first, formation.slots.first);

      final placed = next.entries.firstWhere((e) => e.participantId == 'a');
      expect(placed.zone, MatchCompositionZone.field);
      expect(placed.x, formation.slots.first.position.dx);
      expect(placed.selectionStatus, 'starter');
    });

    test('déposer sur un poste occupé renvoie l’occupant sur le banc', () {
      final slot = formation.slots.first;
      final lineup = lineupOf([
        entry(
          'titulaire',
          zone: MatchCompositionZone.field,
          x: slot.position.dx,
          y: slot.position.dy,
        ),
        entry('remplacant'),
      ]);

      final next = placeEntryOnSlot(lineup, lineup.entries.last, slot);

      expect(
        next.entries.firstWhere((e) => e.participantId == 'titulaire').zone,
        MatchCompositionZone.bench,
      );
      expect(
        next.entries.firstWhere((e) => e.participantId == 'remplacant').zone,
        MatchCompositionZone.field,
      );
    });

    test('deux titulaires échangent leurs postes sans passer par le banc', () {
      final first = formation.slots[0];
      final second = formation.slots[1];
      final lineup = lineupOf([
        entry('a',
            zone: MatchCompositionZone.field,
            x: first.position.dx,
            y: first.position.dy),
        entry('b',
            zone: MatchCompositionZone.field,
            x: second.position.dx,
            y: second.position.dy),
      ]);

      final next = placeEntryOnSlot(
        lineup,
        lineup.entries.firstWhere((e) => e.participantId == 'b'),
        first,
      );

      final a = next.entries.firstWhere((e) => e.participantId == 'a');
      final b = next.entries.firstWhere((e) => e.participantId == 'b');
      expect(a.zone, MatchCompositionZone.field);
      expect(b.zone, MatchCompositionZone.field);
      expect(b.x, first.position.dx);
      expect(a.x, second.position.dx);
    });

    test('renvoyer un titulaire au banc en fait un remplaçant', () {
      final slot = formation.slots.first;
      final lineup = lineupOf([
        entry('a',
            zone: MatchCompositionZone.field,
            x: slot.position.dx,
            y: slot.position.dy),
      ]);

      final next = moveEntryToBench(lineup, lineup.entries.first);

      final moved = next.entries.first;
      expect(moved.zone, MatchCompositionZone.bench);
      expect(moved.x, isNull);
      expect(moved.selectionStatus, 'substitute');
    });
  });

  group('retirer et ajouter un joueur', () {
    test('un joueur retiré sort du compte rendu', () {
      final lineup = lineupOf([entry('a'), entry('b')]);

      final next = removeEntryFromSquad(lineup, lineup.entries.first);

      expect(
        next.entries.firstWhere((e) => e.participantId == 'a').zone,
        MatchCompositionZone.notSelected,
      );
      expect(squadEntries(next).map((e) => e.participantId), ['b']);
      expect(removedEntries(next).map((e) => e.participantId), ['a']);
    });

    test('un joueur réintégré revient sur le banc', () {
      final lineup = lineupOf([
        entry('a', zone: MatchCompositionZone.notSelected),
        entry('b'),
      ]);

      final next = restoreEntryToSquad(lineup, 'a');

      expect(
        next.entries.firstWhere((e) => e.participantId == 'a').zone,
        MatchCompositionZone.bench,
      );
    });
  });

  group('maximum onze titulaires', () {
    MatchComposition fullField() {
      return lineupOf([
        for (var index = 0; index < 11; index += 1)
          entry(
            'f$index',
            zone: MatchCompositionZone.field,
            x: formation.slots[index].position.dx,
            y: formation.slots[index].position.dy,
          ),
        entry('banc'),
      ]);
    }

    test('un douzième joueur venu du banc est refusé', () {
      final lineup = fullField();
      final bench = lineup.entries.last;

      expect(wouldExceedStarterLimit(lineup, bench), isTrue);
    });

    test('déplacer un titulaire déjà sur le terrain reste possible', () {
      final lineup = fullField();
      final starter = lineup.entries.first;

      expect(wouldExceedStarterLimit(lineup, starter), isFalse);
    });
  });

  group('changement de dispositif', () {
    test('les titulaires sont replacés sans franchir la ligne du banc', () {
      final source = formationForCode('4-4-2');
      final lineup = lineupOf(
        [
          entry(
            'gardien',
            zone: MatchCompositionZone.field,
            goalkeeper: true,
            x: source.slots[0].position.dx,
            y: source.slots[0].position.dy,
          ),
          for (var index = 1; index < 5; index += 1)
            entry(
              'j$index',
              zone: MatchCompositionZone.field,
              x: source.slots[index].position.dx,
              y: source.slots[index].position.dy,
            ),
          entry('banc'),
        ],
        formationCode: '4-4-2',
      );

      final next = repositionForFormation(lineup, '4-3-3');

      expect(next.formationCode, formationForCode('4-3-3').code);
      expect(next.entriesFor(MatchCompositionZone.field).length, 5);
      expect(next.entriesFor(MatchCompositionZone.bench).length, 1);
      // Le gardien reste sur le premier poste du nouveau dispositif.
      final keeper =
          next.entries.firstWhere((e) => e.participantId == 'gardien');
      expect(keeper.x, formationForCode('4-3-3').slots.first.position.dx);
    });

    test('un dispositif trop étroit est refusé plutôt que d’éjecter', () {
      final wide = formationForCode('4-4-2');
      final lineup = lineupOf(
        [
          for (var index = 0; index < wide.slots.length; index += 1)
            entry(
              'j$index',
              zone: MatchCompositionZone.field,
              x: wide.slots[index].position.dx,
              y: wide.slots[index].position.dy,
            ),
          entry('extra', zone: MatchCompositionZone.field, x: .5, y: .5),
        ],
        formationCode: '4-4-2',
      );

      expect(
        () => repositionForFormation(lineup, '4-3-3'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
