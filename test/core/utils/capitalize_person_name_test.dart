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

  group('Prénom et initiale extraits d’un nom complet', () {
    // Ces deux fonctions sont la seule règle de réduction « Prénom Nom » →
    // affichage court, partagée entre les Statistiques et la fiche d'un
    // match archivé : elles doivent rester d'accord sur le même cas réel.
    test('firstNameOf isole le premier mot', () {
      expect(firstNameOf('Xavier Grossin'), 'Xavier');
      expect(firstNameOf('  Milan   Couzin  '), 'Milan');
      expect(firstNameOf('Solo'), 'Solo');
      expect(firstNameOf(''), '');
    });

    test('lastNameInitialOf renvoie la première lettre du nom', () {
      expect(lastNameInitialOf('Xavier Grossin'), 'G');
      expect(lastNameInitialOf('Xavier Lacaze'), 'L');
      expect(lastNameInitialOf('Jean Paul Deux Mots'), 'P');
    });

    test('lastNameInitialOf est absent sans nom de famille', () {
      expect(lastNameInitialOf('Solo'), isNull);
      expect(lastNameInitialOf(''), isNull);
    });
  });
}
