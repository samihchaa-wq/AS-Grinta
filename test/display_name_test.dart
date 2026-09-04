import 'package:as_grinta/core/utils/display_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Règle unique d’appellation', () {
    test('le surnom passe avant tout', () {
      expect(
        resolveDisplayName(
          surnom: 'Titi',
          profileFirstName: 'Stéphane',
          fallbackFirstName: 'Steph',
        ),
        'Titi',
      );
    });

    test('un surnom vide n’écrase rien', () {
      // Le client enregistre un surnom non renseigné sous la forme d'une
      // chaîne vide : ce cas est le plus fréquent en production.
      expect(
        resolveDisplayName(surnom: '', profileFirstName: 'Stéphane'),
        'Stéphane',
      );
      expect(
        resolveDisplayName(surnom: '   ', profileFirstName: 'Stéphane'),
        'Stéphane',
      );
    });

    test('le prénom du compte passe avant celui de la fiche', () {
      expect(
        resolveDisplayName(
          profileFirstName: 'Steph',
          fallbackFirstName: 'Stéphane',
        ),
        'Steph',
      );
    });

    test('sans prénom nulle part, on retombe sur le nom', () {
      expect(
        resolveDisplayName(
            fallbackFirstName: '', fallbackLastName: 'Fernandez'),
        'Fernandez',
      );
    });

    test('sans rien du tout, on retombe sur le repli demandé', () {
      expect(resolveDisplayName(), 'Joueur');
      expect(
          resolveDisplayName(fallback: 'Compte sans nom'), 'Compte sans nom');
    });

    test('l’initiale est toujours mise en majuscule', () {
      expect(resolveDisplayName(surnom: 'titi'), 'Titi');
      expect(
          resolveDisplayName(profileFirstName: 'jean-pierre'), 'Jean-Pierre');
    });

    test('une graphie voulue n’est pas défaite', () {
      expect(resolveDisplayName(surnom: 'McDonald'), 'McDonald');
    });
  });

  group('Clé de tri', () {
    test('elle suit le nom réellement affiché', () {
      expect(
        displayNameSortKey(surnom: 'Titi', profileFirstName: 'Stéphane'),
        'titi',
      );
    });

    test('un surnom vide ne range pas tout le monde au même endroit', () {
      // Le défaut historique : trier sur le surnom brut plaçait en tête, dans
      // un ordre arbitraire, tous les comptes dont le surnom vaut ''.
      final sansSurnom = displayNameSortKey(
        surnom: '',
        profileFirstName: 'Stéphane',
      );
      final autreSansSurnom = displayNameSortKey(
        surnom: '',
        profileFirstName: 'Adrien',
      );
      expect(sansSurnom, 'stéphane');
      expect(autreSansSurnom, 'adrien');
      expect(autreSansSurnom.compareTo(sansSurnom) < 0, isTrue);
    });
  });

  group('Appellation d’un invité', () {
    test('prénom seul quand il n’y a pas de nom', () {
      expect(resolveGuestDisplayName(firstName: 'Karim'), 'Karim');
    });

    test('prénom et nom quand les deux sont connus', () {
      expect(
        resolveGuestDisplayName(firstName: 'karim', lastName: 'benali'),
        'Karim Benali',
      );
    });
  });
}
