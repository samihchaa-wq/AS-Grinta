import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthProfile', () {
    test('parses a Supabase profile payload into a domain model', () {
      final profile = AuthProfile.fromJson({
        'first_name': 'Jean',
        'last_name': 'Dupont',
        'avatar_path': '/avatars/jean.png',
        'role': 'admin',
        'is_goalkeeper': true,
        'is_active': true,
      });

      expect(profile.fullName, 'Jean Dupont');
      expect(profile.role, AuthRole.admin);
      expect(profile.role.isAdmin, isTrue);
      expect(profile.isGoalkeeper, isTrue);
      expect(profile.isActive, isTrue);
    });
  });
}
