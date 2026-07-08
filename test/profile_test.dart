import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Profile role handling', () {
    test('maps moderator role correctly', () {
      final profile = AuthProfile.fromJson({
        'first_name': 'Célia',
        'last_name': 'Martin',
        'role': 'moderateur',
        'is_goalkeeper': false,
        'is_active': true,
      });

      expect(profile.role, AuthRole.moderateur);
      expect(profile.role.isModerator, isTrue);
      expect(profile.fullName, 'Célia Martin');
    });
  });
}
