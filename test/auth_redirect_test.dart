import 'package:as_grinta/app/router/auth_redirect.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveAuthRedirect', () {
    test('sends loading states to the loading route without looping', () {
      const state = AuthState(isLoading: true);

      expect(
        resolveAuthRedirect(
          authState: state,
          uri: Uri.parse('/matches'),
          matchedLocation: '/matches',
        ),
        '/auth/loading',
      );
      expect(
        resolveAuthRedirect(
          authState: state,
          uri: Uri.parse('/auth/loading'),
          matchedLocation: '/auth/loading',
        ),
        isNull,
      );
    });

    test('preserves the requested local path for signed-out users', () {
      const state = AuthState(isLoading: false);

      expect(
        resolveAuthRedirect(
          authState: state,
          uri: Uri.parse('/matches/abc?tab=stats'),
          matchedLocation: '/matches/abc',
        ),
        '/auth/sign-in?redirect=%2Fmatches%2Fabc%3Ftab%3Dstats',
      );
    });

    test('allows signed-out users to remain on auth routes', () {
      const state = AuthState(isLoading: false);

      expect(
        resolveAuthRedirect(
          authState: state,
          uri: Uri.parse('/auth/register'),
          matchedLocation: '/auth/register',
        ),
        isNull,
      );
    });

    test('forces password renewal before all other authenticated routes', () {
      const state = AuthState(
        isLoading: false,
        isAuthenticated: true,
        profile: _passwordChangeProfile,
      );

      expect(
        resolveAuthRedirect(
          authState: state,
          uri: Uri.parse('/matches'),
          matchedLocation: '/matches',
        ),
        '/auth/new-password',
      );
      expect(
        resolveAuthRedirect(
          authState: state,
          uri: Uri.parse('/auth/new-password'),
          matchedLocation: '/auth/new-password',
        ),
        isNull,
      );
    });

    test('redirects authenticated users away from auth routes', () {
      const state = AuthState(
        isLoading: false,
        isAuthenticated: true,
        profile: _userProfile,
      );

      expect(
        resolveAuthRedirect(
          authState: state,
          uri: Uri.parse('/auth/sign-in?redirect=%2Fprofile'),
          matchedLocation: '/auth/sign-in',
        ),
        '/profile',
      );
    });

    test('rejects external and auth redirect targets', () {
      const state = AuthState(
        isLoading: false,
        isAuthenticated: true,
        profile: _userProfile,
      );

      for (final target in <String>[
        'https://example.com',
        '//example.com/path',
        '/auth/register',
      ]) {
        final uri = Uri(
          path: '/auth/sign-in',
          queryParameters: {'redirect': target},
        );
        expect(
          resolveAuthRedirect(
            authState: state,
            uri: uri,
            matchedLocation: '/auth/sign-in',
          ),
          '/matches',
        );
      }
    });

    test('blocks privileged routes for regular users', () {
      const state = AuthState(
        isLoading: false,
        isAuthenticated: true,
        profile: _userProfile,
      );

      for (final route in <String>[
        '/admin',
        '/players',
        '/matches/abc/finalize',
      ]) {
        expect(
          resolveAuthRedirect(
            authState: state,
            uri: Uri.parse(route),
            matchedLocation: route,
          ),
          '/matches',
        );
      }
    });

    test('allows privileged routes for administrators', () {
      const state = AuthState(
        isLoading: false,
        isAuthenticated: true,
        profile: _adminProfile,
      );

      for (final route in <String>[
        '/admin',
        '/players',
        '/matches/abc/finalize',
      ]) {
        expect(
          resolveAuthRedirect(
            authState: state,
            uri: Uri.parse(route),
            matchedLocation: route,
          ),
          isNull,
        );
      }
    });

    test('normalizes root aliases to matches', () {
      const state = AuthState(
        isLoading: false,
        isAuthenticated: true,
        profile: _userProfile,
      );

      expect(
        resolveAuthRedirect(
          authState: state,
          uri: Uri.parse('/'),
          matchedLocation: '/',
        ),
        '/matches',
      );
      expect(
        resolveAuthRedirect(
          authState: state,
          uri: Uri.parse('/home'),
          matchedLocation: '/home',
        ),
        '/matches',
      );
    });
  });
}

const _userProfile = AuthProfile(
  id: 'user',
  firstName: 'User',
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

const _passwordChangeProfile = AuthProfile(
  id: 'password-change',
  firstName: 'Password',
  lastName: 'Change',
  role: AuthRole.pronostiqueur,
  isGoalkeeper: false,
  isActive: true,
  mustChangePassword: true,
);
