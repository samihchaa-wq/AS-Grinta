import 'package:as_grinta/features/admin/data/admin_repository.dart';
import 'package:as_grinta/features/admin/presentation/admin_profile_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('groupAdminProfiles', () {
    test('separates pending accounts from validated and archived accounts', () {
      final groups = groupAdminProfiles([
        _profile(id: 'pending', status: 'pending'),
        _profile(id: 'active', status: 'active'),
        _profile(id: 'archived', status: 'archived'),
      ]);

      expect(groups.pending.map((profile) => profile.id), ['pending']);
      expect(
        groups.validated.map((profile) => profile.id),
        ['active', 'archived'],
      );
    });

    test('returns immutable result lists', () {
      final groups = groupAdminProfiles([
        _profile(id: 'pending', status: 'pending'),
      ]);

      expect(
        () => groups.pending.add(_profile(id: 'other', status: 'pending')),
        throwsUnsupportedError,
      );
    });
  });

  group('AdminProfileItem.displayName', () {
    test('prefers the nickname over the official first name', () {
      final profile = _profile(
        id: 'julien',
        status: 'active',
        firstName: 'Julien',
        surnom: 'julio',
      );

      expect(profile.displayName, 'Julio');
      expect(profile.fullName, 'Julien User');
    });

    test('capitalizes the official first name when no nickname exists', () {
      final profile = _profile(
        id: 'romain',
        status: 'active',
        firstName: 'romain',
      );

      expect(profile.displayName, 'Romain');
    });
  });

  group('adminProfileActionPolicy', () {
    test('pending accounts can only be validated or rejected', () {
      final policy = adminProfileActionPolicy(
        profile: _profile(id: 'pending', status: 'pending'),
        currentUserId: 'admin',
      );

      expect(policy.canValidate, isTrue);
      expect(policy.canReject, isTrue);
      expect(policy.canResetPassword, isFalse);
      expect(policy.canArchive, isFalse);
      expect(policy.canReactivate, isFalse);
      expect(policy.canDelete, isFalse);
    });

    test('active accounts can be reset, archived or deleted', () {
      final policy = adminProfileActionPolicy(
        profile: _profile(id: 'active', status: 'active'),
        currentUserId: 'admin',
      );

      expect(policy.canValidate, isFalse);
      expect(policy.canReject, isFalse);
      expect(policy.canResetPassword, isTrue);
      expect(policy.canArchive, isTrue);
      expect(policy.canReactivate, isFalse);
      expect(policy.canDelete, isTrue);
    });

    test('archived accounts can be reactivated but not archived again', () {
      final policy = adminProfileActionPolicy(
        profile: _profile(id: 'archived', status: 'archived'),
        currentUserId: 'admin',
      );

      expect(policy.canResetPassword, isTrue);
      expect(policy.canArchive, isFalse);
      expect(policy.canReactivate, isTrue);
      expect(policy.canDelete, isTrue);
    });

    test('the current administrator cannot manage their own account', () {
      final policy = adminProfileActionPolicy(
        profile: _profile(id: 'admin', status: 'active'),
        currentUserId: 'admin',
      );

      expect(policy.isSelf, isTrue);
      expect(policy.canValidate, isFalse);
      expect(policy.canReject, isFalse);
      expect(policy.canResetPassword, isFalse);
      expect(policy.canArchive, isFalse);
      expect(policy.canReactivate, isFalse);
      expect(policy.canDelete, isFalse);
    });
  });
}

AdminProfileItem _profile({
  required String id,
  required String status,
  String? firstName,
  String surnom = '',
}) {
  return AdminProfileItem(
    id: id,
    firstName: firstName ?? id,
    lastName: 'User',
    surnom: surnom,
    username: id,
    passwordSet: true,
    role: 'pronostiqueur',
    status: status,
  );
}
