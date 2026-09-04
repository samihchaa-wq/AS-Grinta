import 'dart:io';

import 'package:as_grinta/features/sports_management/domain/effectif_validation_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('un effectif jamais publié reste enregistrable sans modification', () {
    expect(
      canPersistEffectif(
        busy: false,
        locked: false,
        dirty: false,
        readyForComposition: false,
      ),
      isTrue,
    );
  });

  test('un effectif publié et inchangé ne propose plus d’enregistrement', () {
    expect(
      canPersistEffectif(
        busy: false,
        locked: false,
        dirty: false,
        readyForComposition: true,
      ),
      isFalse,
    );
  });

  test('une modification rouvre l’enregistrement sur un effectif publié', () {
    expect(
      canPersistEffectif(
        busy: false,
        locked: false,
        dirty: true,
        readyForComposition: true,
      ),
      isTrue,
    );
  });

  test('le verrou du coup d’envoi bloque l’enregistrement', () {
    expect(
      canPersistEffectif(
        busy: false,
        locked: true,
        dirty: true,
        readyForComposition: false,
      ),
      isFalse,
    );
  });

  test('un chargement en cours bloque l’enregistrement', () {
    expect(
      canPersistEffectif(
        busy: true,
        locked: false,
        dirty: true,
        readyForComposition: false,
      ),
      isFalse,
    );
  });

  test('l’écran Effectif branche son bouton sur la règle partagée', () {
    final state = File(
      'lib/features/sports_management/presentation/'
      'admin_squad_plan_page_state.dart',
    ).readAsStringSync();
    final effectif = File(
      'lib/features/sports_management/presentation/'
      'admin_squad_plan_page_effectif.dart',
    ).readAsStringSync();

    expect(state, contains('=> canPersistEffectif('));
    expect(effectif, contains('_canPersistEffectif ? _persistEffectif : null'));
    expect(effectif, isNot(contains('_busy || _locked || !_effectifDirty')));
  });

  test('une compo bloquée offre un raccourci vers l’effectif', () {
    final state = File(
      'lib/features/sports_management/presentation/'
      'admin_squad_plan_page_state.dart',
    ).readAsStringSync();
    final composition = File(
      'lib/features/sports_management/presentation/'
      'admin_squad_plan_page_composition.dart',
    ).readAsStringSync();

    expect(state, contains("Text('Aller à l’effectif')"));
    expect(composition, contains("Text('Aller à l’effectif')"));
  });
}
