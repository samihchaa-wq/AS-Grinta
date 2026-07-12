import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Profile role handling', () {
    test('legacy moderator role maps to admin (rôles fusionnés)', () {
      final profile = AuthProfile.fromJson({
        'first_name': 'Célia',
        'last_name': 'Martin',
        'role': 'moderateur',
        'is_goalkeeper': false,
        'is_active': true,
      });

      expect(profile.role, AuthRole.admin);
      expect(profile.role.isStaff, isTrue);
      expect(profile.fullName, 'Célia Martin');
    });

    test('admin is staff, pronostiqueur is not', () {
      expect(AuthRole.admin.isStaff, isTrue);
      expect(AuthRole.pronostiqueur.isStaff, isFalse);
    });
  });
}
