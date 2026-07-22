import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('expose les 29 formations EA FC avec onze emplacements', () {
    expect(footballFormations, hasLength(29));
    expect(footballFormationByCode(null).code, '4-3-3');
    for (final formation in footballFormations) {
      expect(formation.slots, hasLength(11), reason: formation.code);
      expect(formation.code.length, lessThanOrEqualTo(32));
    }
  });
}
