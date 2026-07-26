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
        contains('majuscule'),
      );
    });

    test('refuse un mot de passe sans minuscule', () {
      expect(
        PasswordPolicy.validate('PHRASECOMPLETE2026'),
        contains('minuscule'),
      );
    });

    test('refuse un mot de passe sans chiffre', () {
      expect(
        PasswordPolicy.validate('GrandePhraseSolide'),
        contains('chiffre'),
      );
    });
  });
}
