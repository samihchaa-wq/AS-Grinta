import 'package:as_grinta/core/utils/name_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Initiales affichées à la place d’une photo', () {
    test('un surnom en plusieurs mots donne ses propres initiales', () {
      // « LB » mélangeait le surnom « Le Mur » et le nom de famille.
      expect(avatarInitials('Le Mur'), 'LM');
      expect(avatarInitials('Samuel Poulain'), 'SP');
    });

    test('un nom affiché d’un seul mot donne ses deux premières lettres', () {
      expect(avatarInitials('Zizou'), 'ZI');
      expect(avatarInitials('Thomas'), 'TH');
      expect(avatarInitials('A'), 'A');
    });

    test('gère les accents et les espaces superflus', () {
      expect(avatarInitials('  élodie  '), 'ÉL');
      expect(avatarInitials('  Élodie   Étienne '), 'ÉÉ');
    });

    test('affiche « ? » quand il n’y a aucun nom', () {
      expect(avatarInitials(''), '?');
      expect(avatarInitials('   '), '?');
    });
  });
}
