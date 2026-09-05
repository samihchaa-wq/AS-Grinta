import 'dart:io';

import 'package:as_grinta/features/sports_management/domain/effectif_validation_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('une décision d’effectif part immédiatement', () {
    expect(
      canSaveEffectifNow(
        busy: false,
        locked: false,
        postMatch: false,
        saving: false,
      ),
      isTrue,
    );
  });

  test('une écriture déjà en cours attend son tour', () {
    expect(
      canSaveEffectifNow(
        busy: false,
        locked: false,
        postMatch: false,
        saving: true,
      ),
      isFalse,
    );
  });

  test('le verrou du coup d’envoi bloque toute écriture', () {
    expect(
      canSaveEffectifNow(
        busy: false,
        locked: true,
        postMatch: false,
        saving: false,
      ),
      isFalse,
    );
  });

  test('après le match, l’effectif ne bouge plus', () {
    expect(
      canSaveEffectifNow(
        busy: false,
        locked: false,
        postMatch: true,
        saving: false,
      ),
      isFalse,
    );
  });

  test('un effectif jamais écrit doit l’être avant la composition', () {
    expect(
      needsInitialEffectifWrite(
        convocationPublished: false,
        busy: false,
        locked: false,
        postMatch: false,
      ),
      isTrue,
    );
  });

  test('un effectif déjà écrit n’est pas réécrit au chargement', () {
    expect(
      needsInitialEffectifWrite(
        convocationPublished: true,
        busy: false,
        locked: false,
        postMatch: false,
      ),
      isFalse,
    );
  });

  test('un match verrouillé ou terminé n’écrit pas d’effectif de départ', () {
    expect(
      needsInitialEffectifWrite(
        convocationPublished: false,
        busy: false,
        locked: true,
        postMatch: false,
      ),
      isFalse,
    );
    expect(
      needsInitialEffectifWrite(
        convocationPublished: false,
        busy: false,
        locked: false,
        postMatch: true,
      ),
      isFalse,
    );
  });

  test('sortir un joueur de la liste d’attente le prévient', () {
    expect(
      convocationPushWillFire(
        wasWaitlisted: true,
        becomesConvoked: true,
        effectifWritten: true,
        postMatch: false,
      ),
      isTrue,
    );
  });

  test('un absent que l’on convoque ne reçoit rien', () {
    expect(
      convocationPushWillFire(
        wasWaitlisted: false,
        becomesConvoked: true,
        effectifWritten: true,
        postMatch: false,
      ),
      isFalse,
    );
  });

  test('sortir un joueur de l’effectif ne prévient personne', () {
    expect(
      convocationPushWillFire(
        wasWaitlisted: true,
        becomesConvoked: false,
        effectifWritten: true,
        postMatch: false,
      ),
      isFalse,
    );
  });

  test('un effectif jamais écrit ne peut prévenir personne', () {
    expect(
      convocationPushWillFire(
        wasWaitlisted: true,
        becomesConvoked: true,
        effectifWritten: false,
        postMatch: false,
      ),
      isFalse,
    );
    expect(
      convocationPushWillFire(
        wasWaitlisted: true,
        becomesConvoked: true,
        effectifWritten: true,
        postMatch: true,
      ),
      isFalse,
    );
  });

  test('l’écran Effectif branche ses écritures sur les règles partagées', () {
    final state = File(
      'lib/features/sports_management/presentation/'
      'admin_squad_plan_page_state.dart',
    ).readAsStringSync();
    final effectif = File(
      'lib/features/sports_management/presentation/'
      'admin_squad_plan_page_effectif.dart',
    ).readAsStringSync();

    expect(state, contains('=> canSaveEffectifNow('));
    expect(state, contains('needsInitialEffectifWrite('));
    expect(effectif, contains('_scheduleEffectifSave();'));
    expect(effectif, contains('convocationPushWillFire('));
    expect(effectif, isNot(contains("label: const Text('Enregistrer')")));
  });

  test('la composition n’attend plus la validation de l’effectif', () {
    final state = File(
      'lib/features/sports_management/presentation/'
      'admin_squad_plan_page_state.dart',
    ).readAsStringSync();
    final composition = File(
      'lib/features/sports_management/presentation/'
      'admin_squad_plan_page_composition.dart',
    ).readAsStringSync();

    expect(state, isNot(contains('Effectif à valider')));
    expect(composition, isNot(contains('Aller à l’effectif')));
    expect(
      composition,
      isNot(contains('L’effectif doit être enregistré avant la composition.')),
    );
  });
}
