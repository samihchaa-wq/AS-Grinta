import 'package:as_grinta/features/matches/data/historical_match_detail_repository.dart';
import 'package:flutter_test/flutter_test.dart';

// NULL signifie « inconnu » ; une liste vide signifie « aucun absent ».
void main() {
  test('absence inconnue reste null pour masquer le module Effectif', () {
    final detail = historicalMatchDetailFromRow({
      'present_names': ['Samih Chaa'],
    });

    expect(detail.presentNames, ['Samih']);
    expect(detail.absentNames, isNull);
  });

  test('une liste absents explicite est conservée même vide', () {
    final withoutAbsent = historicalMatchDetailFromRow({
      'present_names': ['Samih Chaa'],
      'absent_names': <String>[],
    });
    expect(withoutAbsent.absentNames, isEmpty);

    final withAbsent = historicalMatchDetailFromRow({
      'present_names': ['Samih Chaa'],
      'absent_names': ['Florian Dupont'],
    });
    expect(withAbsent.absentNames, ['Florian']);
  });
}
