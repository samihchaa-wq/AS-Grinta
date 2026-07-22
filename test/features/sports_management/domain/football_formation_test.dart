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
}
