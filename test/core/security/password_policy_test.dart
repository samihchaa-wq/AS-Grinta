import 'package:as_grinta/core/security/password_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PasswordPolicy', () {
    test('accepte un mot de passe long avec les trois catégories requises', () {
      expect(PasswordPolicy.validate('GrandePhrase2026'), isNull);
      expect(PasswordPolicy.isValid('GrandePhrase2026'), isTrue);
    });

    test('refuse moins de douze caractères', () {
      expect(PasswordPolicy.validate('Court2026A'), contains('12'));
    });

    test('refuse plus de soixante-douze caractères', () {
      final oversized = '${List.filled(72, 'A').join()}1a';
      expect(PasswordPolicy.validate(oversized), contains('72'));
    });

    test('refuse un mot de passe sans majuscule', () {
      expect(
        PasswordPolicy.validate('phrasecomplete2026'),
        'Ajoute au moins une majuscule de A à Z.',
      );
    });

    test('refuse un mot de passe sans minuscule', () {
      expect(
        PasswordPolicy.validate('PHRASECOMPLETE2026'),
        'Ajoute au moins une minuscule de a à z.',
      );
    });

    test('refuse un mot de passe sans chiffre', () {
      expect(
        PasswordPolicy.validate('GrandePhraseSolide'),
        contains('chiffre'),
      );
    });

    test('une minuscule accentuée ne compte pas comme une majuscule', () {
      expect(
        PasswordPolicy.validate('aaaaaaaaaaé1'),
        'Ajoute au moins une majuscule de A à Z.',
      );
    });

    test('une majuscule accentuée ne compte pas comme une majuscule', () {
      expect(
        PasswordPolicy.validate('Écoledufoot2026'),
        'Ajoute au moins une majuscule de A à Z.',
      );
    });

    test('une minuscule accentuée ne compte pas comme une minuscule', () {
      expect(
        PasswordPolicy.validate('ÉCOLEDUFOOTé2026'),
        'Ajoute au moins une minuscule de a à z.',
      );
    });

    test('les lettres accentuées restent autorisées', () {
      expect(PasswordPolicy.validate('ÉlèveDuFoot2026'), isNull);
    });
  });
}
