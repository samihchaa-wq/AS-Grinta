import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Profile role handling', () {
    test('le rôle modérateur est reconnu, y compris son ancienne graphie', () {
      for (final value in const ['moderateur', 'moderator']) {
        final profile = AuthProfile.fromJson({
          'first_name': 'Célia',
          'last_name': 'Martin',
          'role': value,
          'is_goalkeeper': false,
          'is_active': true,
        });

        expect(profile.role, AuthRole.moderateur, reason: value);
        expect(profile.fullName, 'Célia Martin');
      }
    });

    test('les deux rôles privilégiés sont staff, le joueur non', () {
      expect(AuthRole.admin.isStaff, isTrue);
      expect(AuthRole.moderateur.isStaff, isTrue);
      expect(AuthRole.pronostiqueur.isStaff, isFalse);
    });

    test('seul le modérateur ouvre le module « Modérateur »', () {
      expect(AuthRole.moderateur.isModerator, isTrue);
      expect(AuthRole.admin.isModerator, isFalse);
      expect(AuthRole.pronostiqueur.isModerator, isFalse);
    });
  });
}
