import 'package:as_grinta/app/router/auth_redirect.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sports-management route guard', () {
    test('blocks every sports route while the server flag is disabled', () {
      for (final route in <String>[
        '/matches/m1/availability',
        '/matches/m1/lineup',
        '/matches/m1/vote',
        '/admin/matches/m1/sport-management',
        '/admin/convocations',
        '/admin/waitlist',
      ]) {
        expect(
          resolveAuthRedirect(
            authState: const AuthState(
              isLoading: false,
              isAuthenticated: true,
              profile: _adminProfile,
            ),
            uri: Uri.parse(route),
            matchedLocation: route,
          ),
          '/pronos',
        );
      }
    });

    test('allows player sports routes when the flag is enabled', () {
      for (final route in <String>[
        '/matches/m1/availability',
        '/matches/m1/lineup',
        '/matches/m1/vote',
      ]) {
        expect(
          resolveAuthRedirect(
            authState: const AuthState(
              isLoading: false,
              isAuthenticated: true,
              profile: _playerProfile,
            ),
            uri: Uri.parse(route),
            matchedLocation: route,
            sportsManagementEnabled: true,
          ),
          isNull,
        );
      }
    });

    test(
      'keeps all sports administration routes restricted to administrators',
      () {
        for (final route in <String>[
          '/admin/matches/m1/sport-management',
          '/admin/convocations',
          '/admin/waitlist',
        ]) {
          expect(
            resolveAuthRedirect(
              authState: const AuthState(
                isLoading: false,
                isAuthenticated: true,
                profile: _playerProfile,
              ),
              uri: Uri.parse(route),
              matchedLocation: route,
              sportsManagementEnabled: true,
            ),
            '/pronos',
          );
          expect(
            resolveAuthRedirect(
              authState: const AuthState(
                isLoading: false,
                isAuthenticated: true,
                profile: _adminProfile,
              ),
              uri: Uri.parse(route),
              matchedLocation: route,
              sportsManagementEnabled: true,
            ),
            isNull,
          );
        }
      },
    );
  });
}

const _playerProfile = AuthProfile(
  id: 'player',
  firstName: 'Player',
  lastName: 'One',
  role: AuthRole.pronostiqueur,
  isGoalkeeper: false,
  isActive: true,
  mustChangePassword: false,
);

const _adminProfile = AuthProfile(
  id: 'admin',
  firstName: 'Admin',
  lastName: 'One',
  role: AuthRole.admin,
  isGoalkeeper: false,
  isActive: true,
  mustChangePassword: false,
);
