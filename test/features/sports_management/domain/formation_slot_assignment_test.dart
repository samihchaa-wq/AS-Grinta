import 'package:as_grinta/features/sports_management/domain/formation_slot_assignment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('assignEntriesToSlots', () {
    test('deux joueurs proches du même poste occupent deux postes distincts',
        () {
      const slots = [Offset(.5, .8), Offset(.5, .6)];
      // Les deux joueurs sont plus près du premier poste que du second.
      const entries = [Offset(.50, .79), Offset(.52, .77)];

      final assignment = assignEntriesToSlots(
        slotPositions: slots,
        entryPositions: entries,
      );

      expect(assignment.length, 2);
      expect(assignment.values.toSet().length, 2, reason: 'aucun doublon');
      expect(assignment[0], 0, reason: 'le plus proche garde son poste');
      expect(assignment[1], 1);
    });

    test('un joueur loin de tous les postes reste visible', () {
      const slots = [Offset(.5, .8), Offset(.5, .2)];
      const entries = [Offset(.5, .8), Offset(.05, .05)];

      final assignment = assignEntriesToSlots(
        slotPositions: slots,
        entryPositions: entries,
      );

      expect(assignment.values.toSet(), {0, 1});
    });

    test('plus de joueurs que de postes : les postes restent tous occupés', () {
      const slots = [Offset(.5, .8)];
      const entries = [Offset(.5, .5), Offset(.5, .79)];

      final assignment = assignEntriesToSlots(
        slotPositions: slots,
        entryPositions: entries,
      );

      expect(assignment.length, 1);
      expect(assignment[0], 1);
    });

    test('aucun joueur : aucun poste occupé', () {
      final assignment = assignEntriesToSlots(
        slotPositions: const [Offset(.5, .8)],
        entryPositions: const [],
      );

      expect(assignment, isEmpty);
    });
  });

  group('nearestSlotIndex', () {
    test('tient compte de la hauteur réelle du terrain', () {
      // Le premier poste est décalé de .12 en largeur, le second de .11 en
      // hauteur. En coordonnées brutes le second semble plus proche ; à
      // l'écran, le terrain étant bien plus haut que large, .11 en hauteur
      // fait beaucoup plus de pixels que .12 en largeur.
      const slots = [Offset(.38, .50), Offset(.50, .39)];

      final index = nearestSlotIndex(slots, const Offset(.50, .50));

      expect(index, 0);
    });

    test('sans poste, aucune cible', () {
      expect(nearestSlotIndex(const [], const Offset(.5, .5)), isNull);
    });
  });
}
