import 'dart:io';

import 'package:as_grinta/features/sports_management/domain/composition_publication_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la première mise en ligne prévient les convoqués', () {
    expect(
      compositionPublicationWillNotify(
        alreadyPublished: false,
        sheetNamesPlayers: true,
        postMatch: false,
      ),
      isTrue,
    );
  });

  test('une retouche ne prévient personne', () {
    expect(
      compositionPublicationWillNotify(
        alreadyPublished: true,
        sheetNamesPlayers: true,
        postMatch: false,
      ),
      isFalse,
    );
  });

  test('une feuille sans aucun joueur ne prévient personne', () {
    expect(
      compositionPublicationWillNotify(
        alreadyPublished: false,
        sheetNamesPlayers: false,
        postMatch: false,
      ),
      isFalse,
    );
  });

  test('après le match, la feuille n’annonce plus rien', () {
    expect(
      compositionPublicationWillNotify(
        alreadyPublished: false,
        sheetNamesPlayers: true,
        postMatch: true,
      ),
      isFalse,
    );
  });

  test('les deux écrans de composition branchent la même règle', () {
    final composition = File(
      'lib/features/sports_management/presentation/'
      'admin_squad_plan_page_composition.dart',
    ).readAsStringSync();
    final internal = File(
      'lib/features/sports_management/presentation/widgets/'
      'internal_team_composition_view.dart',
    ).readAsStringSync();

    expect(composition, contains('compositionPublicationWillNotify('));
    expect(internal, contains('compositionPublicationWillNotify('));
    for (final source in [composition, internal]) {
      expect(source, contains('Publier la composition ?'));
      expect(source, contains('enverra une notification à tous les '));
      expect(source, contains('Valider'));
    }
  });

  test('le match entre nous s’appuie sur l’état connu du serveur', () {
    final internal = File(
      'lib/features/sports_management/presentation/widgets/'
      'internal_team_composition_view.dart',
    ).readAsStringSync();

    // Deviner d'après la feuille se trompait après une remise à zéro.
    expect(internal, contains('composition.notificationSent'));
    expect(internal, contains('alreadyPublished: _notificationSent'));
  });
}
