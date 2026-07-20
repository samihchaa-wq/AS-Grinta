import 'package:as_grinta/app/router/auth_redirect.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('blocks composition routes while the module is disabled', () {
    for (final route in <String>[
      '/admin/composition',
      '/matches/match-1/lineup',
    ]) {
      expect(
        resolveAuthRedirect(
          authState: _adminState,
          uri: Uri.parse(route),
          matchedLocation: route,
          sportsManagementEnabled: false,
        ),
        '/pronos',
      );
    }
  });

  test('allows composition routes for an administrator when enabled', () {
    for (final route in <String>[
      '/admin/composition',
      '/matches/match-1/lineup',
    ]) {
      expect(
        resolveAuthRedirect(
          authState: _adminState,
          uri: Uri.parse(route),
          matchedLocation: route,
          sportsManagementEnabled: true,
        ),
        isNull,
      );
    }
  });

  test('still blocks the admin composition route for a regular player', () {
    expect(
      resolveAuthRedirect(
        authState: _playerState,
        uri: Uri.parse('/admin/composition'),
        matchedLocation: '/admin/composition',
        sportsManagementEnabled: true,
      ),
      '/pronos',
    );
  });
}

const _adminState = AuthState(
  isLoading: false,
  isAuthenticated: true,
  profile: AuthProfile(
    id: 'admin',
    firstName: 'Admin',
    lastName: 'One',
    role: AuthRole.admin,
    isGoalkeeper: false,
    isActive: true,
    mustChangePassword: false,
  ),
);

const _playerState = AuthState(
  isLoading: false,
  isAuthenticated: true,
  profile: AuthProfile(
    id: 'player',
    firstName: 'Player',
    lastName: 'One',
    role: AuthRole.pronostiqueur,
    isGoalkeeper: false,
    isActive: true,
    mustChangePassword: false,
  ),
);
