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
        '/auth/loading?redirect=%2Fmatches',
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

    test('carries the recovery destination through the loading route', () {
      const loading = AuthState(isLoading: true);

      expect(
        resolveAuthRedirect(
          authState: loading,
          uri: Uri.parse('/auth/new-password?recovery=1'),
          matchedLocation: '/auth/new-password',
        ),
        '/auth/loading?redirect=%2Fauth%2Fnew-password%3Frecovery%3D1',
      );

      const resolved = AuthState(isLoading: false);

      expect(
        resolveAuthRedirect(
          authState: resolved,
          uri: Uri.parse(
            '/auth/loading?redirect=%2Fauth%2Fnew-password%3Frecovery%3D1',
          ),
          matchedLocation: '/auth/loading',
        ),
        '/auth/new-password?recovery=1',
      );
    });

    test('restores a non-auth destination after signing in', () {
      const state = AuthState(isLoading: false);

      expect(
        resolveAuthRedirect(
          authState: state,
          uri: Uri.parse('/auth/loading?redirect=%2Fmatches%2Fabc'),
          matchedLocation: '/auth/loading',
        ),
        '/auth/sign-in?redirect=%2Fmatches%2Fabc',
      );
    });

    test(
      'leaves the loading route once loading finishes without a session',
      () {
        const state = AuthState(isLoading: false);

        expect(
          resolveAuthRedirect(
            authState: state,
            uri: Uri.parse('/auth/loading'),
            matchedLocation: '/auth/loading',
          ),
          '/auth/sign-in',
        );
      },
    );

    test(
      'keeps a valid session on loading while the profile is unavailable',
      () {
        const state = AuthState(
          isLoading: false,
          hasSession: true,
          error: 'Connexion temporairement indisponible.',
        );

        expect(
          resolveAuthRedirect(
            authState: state,
            uri: Uri.parse('/matches'),
            matchedLocation: '/matches',
          ),
          '/auth/loading?redirect=%2Fmatches',
        );
        expect(
          resolveAuthRedirect(
            authState: state,
            uri: Uri.parse('/auth/loading'),
            matchedLocation: '/auth/loading',
          ),
          isNull,
        );
      },
    );

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
        hasSession: true,
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
        hasSession: true,
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
        hasSession: true,
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
        hasSession: true,
        profile: _userProfile,
      );

      for (final route in <String>[
        '/admin',
        '/admin/administration',
        '/admin/badges',
        '/admin/matches',
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
          reason: route,
        );
      }
    });

    test('allows every privileged route for administrators', () {
      const state = AuthState(
        isLoading: false,
        isAuthenticated: true,
        hasSession: true,
        profile: _adminProfile,
      );

      for (final route in <String>[
        '/admin',
        '/admin/administration',
        '/admin/badges',
        '/admin/matches',
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
          reason: route,
        );
      }
    });

    test('normalizes root and former home aliases to Matchs', () {
      const state = AuthState(
        isLoading: false,
        isAuthenticated: true,
        hasSession: true,
        profile: _userProfile,
      );

      for (final route in <String>['/', '/home', '/accueil']) {
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
