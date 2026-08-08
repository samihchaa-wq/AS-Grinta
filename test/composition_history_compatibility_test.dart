import 'dart:io';

import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compatibilité des dispositifs historiques', () {
    test('4-4-2 historique pointe vers le 4-4-2 à plat actuel', () {
      final legacy = formationForCodeOrNull('4-4-2');
      final current = formationForCodeOrNull('4-4-2 à plat');

      expect(legacy, isNotNull);
      expect(legacy!.code, '4-4-2 à plat');
      expect(legacy.slotLabels, current!.slotLabels);
    });

    test('un code inconnu est détectable sans fallback silencieux', () {
      expect(formationForCodeOrNull('formation-future'), isNull);
      expect(formationForCode('formation-future').code, kDefaultFormationCode);
    });
  });

  test('ouvrir une composition sauvegardée ne recale jamais ses joueurs', () {
    final source = File(
      'lib/features/sports_management/presentation/'
      'admin_squad_plan_page_composition.dart',
    ).readAsStringSync();

    expect(source, contains('return _preserveSavedLayout('));
    expect(
      RegExp(r'return _rescueOrphans\(\s*saved\.copyWith').hasMatch(source),
      isFalse,
    );
    expect(
      source,
      contains('les coordonnées x/y sauvegardées restent la source de vérité'),
    );
  });
}
