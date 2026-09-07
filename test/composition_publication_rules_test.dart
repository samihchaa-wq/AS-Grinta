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

  test('le match entre nous ne publie que depuis les deux terrains', () {
    final composition = File(
      'lib/features/sports_management/presentation/'
      'admin_squad_plan_page_composition.dart',
    ).readAsStringSync();
    final internal = File(
      'lib/features/sports_management/presentation/widgets/'
      'internal_team_composition_view.dart',
    ).readAsStringSync();

    expect(composition, contains('compositionPublicationWillNotify('));
    expect(composition, contains('Publier la composition ?'));

    expect(internal, contains('compositionPublicationWillNotify('));
    expect(internal, contains('Mettre les compositions en ligne ?'));
    expect(internal, contains('Les compositions sont '));
    expect(internal, contains('en ligne » aux joueurs convoqués.'));
    expect(internal, isNot(contains('Publier la composition ?')));

    final paperStart = internal.indexOf('Future<void> _savePaper()');
    final visualStart = internal.indexOf('Future<void> _save()', paperStart);
    expect(paperStart, greaterThanOrEqualTo(0));
    expect(visualStart, greaterThan(paperStart));
    final paperSource = internal.substring(paperStart, visualStart);
    expect(paperSource, isNot(contains('compositionPublicationWillNotify(')));
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
