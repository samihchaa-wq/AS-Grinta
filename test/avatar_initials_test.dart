import 'package:as_grinta/core/utils/name_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Initiales affichées à la place d’une photo', () {
    test('combine le prénom et le nom quand le nom est connu', () {
      expect(avatarInitials('Julien', lastName: 'Dupont'), 'JD');
      expect(avatarInitials('Alyoun', lastName: 'martin'), 'AM');
    });

    test('distingue deux joueurs au même prénom', () {
      expect(
        avatarInitials('Julien', lastName: 'Chaa'),
        isNot(avatarInitials('Julien', lastName: 'Durand')),
      );
    });

    test('lit le nom dans le libellé quand il n’est pas fourni à part', () {
      expect(avatarInitials('Samuel Poulain'), 'SP');
    });

    test('retombe sur les deux premières lettres sans nom de famille', () {
      expect(avatarInitials('Pipo'), 'PI');
      expect(avatarInitials('Aki', lastName: ''), 'AK');
      expect(avatarInitials('A'), 'A');
    });

    test('gère les accents et les espaces superflus', () {
      expect(avatarInitials('  élodie  ', lastName: '  Étienne '), 'ÉÉ');
    });

    test('affiche « ? » quand il n’y a aucun nom', () {
      expect(avatarInitials(''), '?');
      expect(avatarInitials('   ', lastName: '  '), '?');
    });
  });
}
