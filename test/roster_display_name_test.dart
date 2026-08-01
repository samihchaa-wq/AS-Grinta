import 'package:as_grinta/features/players/data/roster_repository.dart';
import 'package:flutter_test/flutter_test.dart';

RosterPlayer _player({
  String firstName = 'Stéphane',
  String lastName = 'Fernandez',
  String? profileId,
  String? profileFirstName,
  String? surnom,
}) {
  return RosterPlayer(
    id: 'p1',
    firstName: firstName,
    lastName: lastName,
    isGoalkeeper: false,
    isCoach: false,
    isActive: true,
    linkedProfileId: profileId,
    linkedProfileName: profileFirstName,
    linkedProfileUsername: null,
    linkedProfileSurnom: surnom,
  );
}

void main() {
  group('Nom affiché d’un joueur de l’effectif', () {
    test('le prénom du compte rattaché l’emporte sur celui de la fiche', () {
      // Le cas réel : l'admin a saisi « Stéphane », le joueur s'est inscrit
      // sous « Steph ». C'est son choix qui doit s'afficher.
      final player = _player(profileId: 'a', profileFirstName: 'Steph');
      expect(player.displayName, 'Steph');
      expect(player.rosterName, 'Stéphane');
    });

    test('le surnom passe devant le prénom du compte', () {
      final player = _player(
        profileId: 'a',
        profileFirstName: 'Steph',
        surnom: 'Titi',
      );
      expect(player.displayName, 'Titi');
    });

    test('sans compte rattaché, la fiche fait foi', () {
      expect(_player().displayName, 'Stéphane');
    });

    test('un compte sans prénom ne masque pas la fiche', () {
      final player = _player(profileId: 'a', profileFirstName: '  ');
      expect(player.displayName, 'Stéphane');
    });

    test('sans prénom nulle part, on retombe sur le nom', () {
      final player = _player(firstName: '');
      expect(player.displayName, 'Fernandez');
    });
  });
}
