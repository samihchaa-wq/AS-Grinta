import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Profile role handling', () {
    test('les anciennes valeurs modérateur restent compatibles comme admin', () {
      for (final value in const ['moderateur', 'moderator']) {
        final profile = AuthProfile.fromJson({
          'first_name': 'Célia',
          'last_name': 'Martin',
          'role': value,
          'is_goalkeeper': false,
          'is_active': true,
        });

        expect(profile.role, AuthRole.admin, reason: value);
        expect(profile.fullName, 'Célia Martin');
      }
    });

    test('seul le rôle admin possède les droits de gestion', () {
      expect(AuthRole.admin.isStaff, isTrue);
      expect(AuthRole.admin.isAdmin, isTrue);
      expect(AuthRole.pronostiqueur.isStaff, isFalse);
      expect(AuthRole.pronostiqueur.isAdmin, isFalse);
    });

    test('le libellé utilisateur ne modifie pas la valeur serveur historique', () {
      expect(AuthRole.pronostiqueur.label, 'Utilisateur');
      expect(AuthRole.admin.label, 'Admin');
    });
  });
}
