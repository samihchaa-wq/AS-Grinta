import 'package:as_grinta/app/router/auth_redirect.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('auth router exhausts roles, flags, password states and routes', () {
    final scenarios = <_AuthScenario>[
      const _AuthScenario(
        'loading',
        AuthState(isLoading: true, isAuthenticated: false),
      ),
      const _AuthScenario(
        'anonymous',
        AuthState(isLoading: false, isAuthenticated: false),
      ),
      _AuthScenario('player', _authenticated(_profile(AuthRole.pronostiqueur))),
      _AuthScenario('admin', _authenticated(_profile(AuthRole.admin))),
      _AuthScenario(
        'player_password_change',
        _authenticated(
          _profile(AuthRole.pronostiqueur, mustChangePassword: true),
        ),
      ),
      _AuthScenario(
        'admin_password_change',
        _authenticated(_profile(AuthRole.admin, mustChangePassword: true)),
      ),
      _AuthScenario(
        'inactive_profile',
        AuthState(
          isLoading: false,
          isAuthenticated: false,
          profile: _profile(AuthRole.pronostiqueur, isActive: false),
        ),
      ),
    ];
    final routes = <_RouteCase>[
      _route('/'),
      _route('/home'),
      _route('/accueil'),
      _route('/matches'),
      _route('/matches/m1'),
      _route('/matches/m1/prediction'),
      _route('/matches/m1/availability'),
      _route('/matches/m1/lineup'),
      _route('/matches/m1/vote'),
      _route('/matches/m1/finalize'),
      _route('/matches/m1/composition'),
      _route('/matches/m1/guests'),
      _route('/admin'),
      _route('/admin/administration'),
      _route('/admin/matches'),
      _route('/admin/composition'),
      _route('/admin/guests'),
      _route('/admin/motm'),
      _route('/admin/waitlist'),
      _route('/admin/matches/m1/sport-management'),
      _route('/players'),
      _route('/profile'),
      _route('/stats'),
      _route('/notifications'),
      _route('/auth/loading'),
      _route('/auth/sign-in'),
      _route('/auth/register'),
      _route('/auth/new-password'),
      _route('/auth/sign-in?redirect=%2Fstats', matched: '/auth/sign-in'),
      _route('/auth/sign-in?redirect=%2Fhome', matched: '/auth/sign-in'),
      _route(
        '/auth/sign-in?redirect=%2Fpronos%3Fcategory%3Dmatches',
        matched: '/auth/sign-in',
      ),
      _route('/auth/sign-in?redirect=%2F%2Fevil.test', matched: '/auth/sign-in'),
      _route(
        '/auth/sign-in?redirect=https%3A%2F%2Fevil.test',
        matched: '/auth/sign-in',
      ),
      _route(
        '/auth/sign-in?redirect=%2Fauth%2Fregister',
        matched: '/auth/sign-in',
      ),
    ];

    var cases = 0;
    for (final scenario in scenarios) {
      for (final route in routes) {
        for (final sportsEnabled in [false, true]) {
          cases += 1;
          final observed = resolveAuthRedirect(
            authState: scenario.state,
            uri: route.uri,
            matchedLocation: route.matchedLocation,
            sportsManagementEnabled: sportsEnabled,
          );
          final expected = _expectedRedirect(
            authState: scenario.state,
            uri: route.uri,
            matchedLocation: route.matchedLocation,
            sportsManagementEnabled: sportsEnabled,
          );
          expect(
            observed,
            expected,
            reason: 'scenario=${scenario.name} route=${route.uri} '
                'matched=${route.matchedLocation} sports=$sportsEnabled',
          );
        }
      }
    }

    expect(cases, scenarios.length * routes.length * 2);
    // ignore: avoid_print
    print('STATE_SPACE auth_router cases=$cases status=passed');
  });
}

String? _expectedRedirect({
  required AuthState authState,
  required Uri uri,
  required String matchedLocation,
  required bool sportsManagementEnabled,
}) {
  if (authState.isLoading) {
    return matchedLocation == '/auth/loading' ? null : '/auth/loading';
  }

  final authenticated = authState.isAuthenticated;
  final mustChangePassword = authState.profile?.mustChangePassword == true;
  final authRoute = matchedLocation.startsWith('/auth');

  if (matchedLocation == '/auth/loading' && !authenticated) {
    return '/auth/sign-in';
  }
  if (authenticated && mustChangePassword) {
    return matchedLocation == '/auth/new-password'
        ? null
        : '/auth/new-password';
  }
  if (matchedLocation == '/auth/new-password' && !mustChangePassword) {
    return '/matches';
  }
  if (!authenticated && !authRoute && matchedLocation != '/') {
    return '/auth/sign-in?redirect=${Uri.encodeComponent(uri.toString())}';
  }
  if (authenticated && authRoute) {
    return _safeRedirect(uri.queryParameters['redirect']) ?? '/matches';
  }
  if (const {'/', '/home', '/accueil'}.contains(matchedLocation)) {
    return '/matches';
  }

  final segments = uri.pathSegments.where((value) => value.isNotEmpty).toList();
  final suffix = segments.isEmpty ? '' : segments.last;
  final playerSportRoute = segments.length == 3 &&
      segments.first == 'matches' &&
      const {
        'availability',
        'lineup',
        'vote',
        'composition',
        'guests',
      }.contains(suffix);
  final adminSportMatchRoute = segments.length == 4 &&
      segments[0] == 'admin' &&
      segments[1] == 'matches' &&
      suffix == 'sport-management';
  final adminSportRootRoute = segments.length == 2 &&
      segments.first == 'admin' &&
      const {'composition', 'guests', 'motm', 'waitlist'}.contains(suffix);
  final sportRoute =
      playerSportRoute || adminSportMatchRoute || adminSportRootRoute;

  if (sportRoute && !sportsManagementEnabled) {
    if (segments.length == 3 &&
        segments.first == 'matches' &&
        suffix == 'lineup') {
      return '/matches/${segments[1]}/prediction';
    }
    return '/matches';
  }

  final role = authState.profile?.role;
  final admin = role == AuthRole.admin;
  final finalization = matchedLocation.startsWith('/matches/') &&
      matchedLocation.endsWith('/finalize');
  final adminRoot =
      matchedLocation == '/admin' || matchedLocation.startsWith('/admin/');
  final matchAdmin = segments.length == 3 &&
      segments.first == 'matches' &&
      const {'composition', 'guests'}.contains(suffix);

  if (finalization && !admin) return '/matches';
  if ((adminRoot || matchAdmin || matchedLocation == '/players') && !admin) {
    return '/matches';
  }
  return null;
}

String? _safeRedirect(String? value) {
  if (value == null || value.isEmpty || value.startsWith('//')) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  if (!uri.path.startsWith('/') || uri.path.startsWith('/auth')) return null;
  if (const {'/home', '/accueil'}.contains(uri.path)) return '/matches';
  if (uri.path == '/pronos' && uri.queryParameters['category'] == 'matches') {
    return '/matches';
  }
  return uri.toString();
}

AuthState _authenticated(AuthProfile profile) => AuthState(
      isLoading: false,
      isAuthenticated: true,
      profile: profile,
    );

AuthProfile _profile(
  AuthRole role, {
  bool mustChangePassword = false,
  bool isActive = true,
}) {
  return AuthProfile(
    id: 'profile-${role.name}-$mustChangePassword-$isActive',
    firstName: 'Test',
    lastName: role.name,
    role: role,
    isGoalkeeper: false,
    isActive: isActive,
    mustChangePassword: mustChangePassword,
  );
}

_RouteCase _route(String location, {String? matched}) => _RouteCase(
      Uri.parse(location),
      matched ?? Uri.parse(location).path,
    );

class _AuthScenario {
  const _AuthScenario(this.name, this.state);

  final String name;
  final AuthState state;
}

class _RouteCase {
  const _RouteCase(this.uri, this.matchedLocation);

  final Uri uri;
  final String matchedLocation;
}
