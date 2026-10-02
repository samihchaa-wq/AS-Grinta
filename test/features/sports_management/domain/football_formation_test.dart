import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la feuille de match expose 22 postes normalisés et distincts', () {
    expect(matchSheetSlots, hasLength(22));

    // Exactement un gardien.
    expect(
      matchSheetSlots.where((slot) => slot.label == 'GB'),
      hasLength(1),
    );

    // Toutes les positions sont normalisées dans le terrain.
    for (final slot in matchSheetSlots) {
      expect(slot.position.dx, inInclusiveRange(0.0, 1.0), reason: slot.label);
      expect(slot.position.dy, inInclusiveRange(0.0, 1.0), reason: slot.label);
      expect(slot.label, isNotEmpty);
    }

    // Les étiquettes sont uniques.
    final labels = matchSheetSlots.map((slot) => slot.label).toSet();
    expect(labels, hasLength(matchSheetSlots.length));

    // Deux postes ne se superposent jamais exactement (chevauchement total).
    for (var i = 0; i < matchSheetSlots.length; i += 1) {
      for (var j = i + 1; j < matchSheetSlots.length; j += 1) {
        final distance =
            (matchSheetSlots[i].position - matchSheetSlots[j].position)
                .distance;
        expect(distance, greaterThan(0.0),
            reason: '${matchSheetSlots[i].label}'
                ' vs ${matchSheetSlots[j].label}');
      }
    }
  });

  group('catalogue des dispositifs', () {
    // Taille d'une vignette de joueur sur un téléphone, en fraction du
    // terrain : FormationMarkerMetrics donne une largeur de terrain / 5,6
    // et une hauteur 1,32 fois plus grande, sur un terrain de ratio 0,68.
    const markerWidth = 1 / 5.6;
    const markerHeight = markerWidth * 1.32 * .68;

    test('chaque dispositif aligne 11 postes distincts, gardien en premier',
        () {
      for (final formation in footballFormations) {
        expect(formation.slots, hasLength(11), reason: formation.code);
        expect(formation.slots.first.label, 'GB', reason: formation.code);
        expect(
          formation.slotLabels.toSet(),
          hasLength(11),
          reason: formation.code,
        );
        final defenders =
            formation.slotLabels.where((label) => label.startsWith('D')).length;
        expect(defenders, formation.defenderLine, reason: formation.code);
      }
    });

    test('deux joueurs d’un même dispositif ne se chevauchent jamais', () {
      for (final formation in footballFormations) {
        final slots = formation.slots;
        for (var i = 0; i < slots.length; i += 1) {
          for (var j = i + 1; j < slots.length; j += 1) {
            final delta = slots[i].position - slots[j].position;
            final overlaps = delta.dx.abs() < markerWidth - .001 &&
                delta.dy.abs() < markerHeight - .001;
            expect(
              overlaps,
              isFalse,
              reason: '${formation.code} : ${slots[i].label} chevauche '
                  '${slots[j].label}',
            );
          }
        }
      }
    });

    test('aucun joueur n’est collé au bord du terrain', () {
      for (final formation in footballFormations) {
        for (final slot in formation.slots) {
          final reason = '${formation.code} ${slot.label}';
          expect(slot.position.dx, inInclusiveRange(.08, .92), reason: reason);
          expect(slot.position.dy, inInclusiveRange(.12, .89), reason: reason);
        }
      }
    });

    test('chaque dispositif est symétrique gauche / droite', () {
      for (final formation in footballFormations) {
        final mirrored = {
          for (final slot in formation.slots)
            '${(slot.position.dx * 100).round()}:'
                '${(slot.position.dy * 100).round()}',
        };
        for (final slot in formation.slots) {
          expect(
            mirrored.contains('${(100 - slot.position.dx * 100).round()}:'
                '${(slot.position.dy * 100).round()}'),
            isTrue,
            reason: '${formation.code} ${slot.label} sans symétrique',
          );
        }
      }
    });

    test('un poste reste près de son ancienne place sur la grille', () {
      // Les compositions enregistrées gardent leurs coordonnées : l'éditeur
      // retrouve un joueur sur son poste jusqu'à 0,12 de distance.
      for (final formation in footballFormations) {
        for (final slot in formation.slots) {
          final reference = matchSheetSlotPositions[slot.label]!;
          expect(
            (slot.position - reference).distance,
            lessThan(.11),
            reason: '${formation.code} ${slot.label}',
          );
        }
      }
    });

    test('un joueur posé sur un poste est relu avec le nom de ce poste', () {
      for (final formation in footballFormations) {
        for (final slot in formation.slots) {
          expect(
            nearestMatchSheetSlotLabel(slot.position),
            slot.label,
            reason: formation.code,
          );
        }
      }
      for (final slot in matchSheetSlots) {
        expect(nearestMatchSheetSlotLabel(slot.position), slot.label);
      }
    });
  });
}
