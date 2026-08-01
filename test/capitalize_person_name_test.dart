import 'package:as_grinta/core/utils/name_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Majuscule à l’initiale d’un nom', () {
    test('remet l’initiale sur un prénom saisi en minuscules', () {
      // Le cas réel : un joueur s'était inscrit sous « romain ».
      expect(capitalizePersonName('romain'), 'Romain');
    });

    test('traite chaque partie d’un nom composé', () {
      expect(capitalizePersonName('jean-pierre'), 'Jean-Pierre');
      expect(capitalizePersonName('marie claire'), 'Marie Claire');
      expect(capitalizePersonName('d’artagnan'), 'D’Artagnan');
      expect(capitalizePersonName("o'connor"), "O'Connor");
    });

    test('ne défait pas une graphie voulue', () {
      // On ne force que l'initiale : le reste du mot est laissé tel quel.
      expect(capitalizePersonName('CHÂA'), 'CHÂA');
      expect(capitalizePersonName('McDonald'), 'McDonald');
    });

    test('respecte les accents', () {
      expect(capitalizePersonName('élodie'), 'Élodie');
      expect(capitalizePersonName('Stéphane'), 'Stéphane');
    });

    test('supporte le vide et les espaces superflus', () {
      expect(capitalizePersonName(''), '');
      expect(capitalizePersonName('   '), '');
      expect(capitalizePersonName('  steph  '), 'Steph');
    });
  });
}
