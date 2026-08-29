import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a simple back from a match does not request a calendar refocus', () {
    final source = File(
      'lib/app/shell/app_shell.dart',
    ).readAsStringSync();

    // Revenir d'une fiche match vers /matches reste dans la branche Calendrier.
    // Le shell ne doit donc plus déduire un re-focus du seul changement d'URL :
    // sinon Défilé saute à « Précédent élément » et Par mois au mois courant.
    expect(source, isNot(contains('_previousLocationPath')));
    expect(source, isNot(contains('returnedToMatchesRoot')));

    // Une vraie bascule vers la branche Calendrier continue en revanche de
    // demander le recentrage attendu.
    expect(source, contains('if (switchedToMatchesBranch)'));
    expect(source, contains('_scheduleMatchFocus();'));
  });
}
