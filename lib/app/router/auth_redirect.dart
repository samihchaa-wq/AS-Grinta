import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';

String? resolveAuthRedirect({
  required AuthState authState,
  required Uri uri,
  required String matchedLocation,
  bool sportsManagementEnabled = false,
}) {
  final location = matchedLocation;

  if (authState.isLoading) {
    return location == '/auth/loading' ? null : '/auth/loading';
  }

  // /auth/loading est purement transitoire : dès que le chargement est terminé,
  // on doit le quitter, sinon on reste bloqué dessus. Sans session on part sur
  // la connexion ; avec session, on laisse la suite router vers l'accueil.
  if (location == '/auth/loading' && !authState.isAuthenticated) {
    return '/auth/sign-in';
  }

  final isPasswordChangeRoute = location == '/auth/new-password';
  final mustChangePassword = authState.profile?.mustChangePassword == true;

  if (authState.isAuthenticated && mustChangePassword) {
    return isPasswordChangeRoute ? null : '/auth/new-password';
  }
  if (isPasswordChangeRoute && !mustChangePassword) return '/accueil';

  final isAuthRoute = location.startsWith('/auth');
  if (!authState.isAuthenticated && !isAuthRoute && location != '/') {
    return '/auth/sign-in?redirect=${Uri.encodeComponent(uri.toString())}';
  }

  if (authState.isAuthenticated && isAuthRoute) {
    final redirect = _safeLocalRedirect(uri.queryParameters['redirect']);
    return redirect ?? '/accueil';
  }

  if (location == '/' || location == '/home') {
    return '/accueil';
  }
  if (location == '/matches') {
    return '/pronos?category=matches';
  }

  if (_isSportsManagementRoute(uri) && !sportsManagementEnabled) {
    return '/pronos';
  }

  final role = authState.profile?.role;
  final isAdmin = role == AuthRole.admin;
  final isStaff = role?.isStaff == true;
  final isFinalizationRoute =
      location.startsWith('/matches/') && location.endsWith('/finalize');
  final isAdminRoute = location == '/admin' || location.startsWith('/admin/');
  final isPlayersRoute = location == '/players';

  if (isFinalizationRoute && !isAdmin) return '/pronos';
  if (isAdminRoute && !isStaff) return '/pronos';
  if (isPlayersRoute && !isStaff) return '/pronos';
  return null;
}

bool _isSportsManagementRoute(Uri uri) {
  final segments =
      uri.pathSegments.where((segment) => segment.isNotEmpty).toList();

  final isPlayerMatchRoute = segments.length == 3 &&
      segments.first == 'matches' &&
      const {'availability', 'lineup', 'vote'}.contains(segments.last);
  final isAdminMatchRoute = segments.length == 4 &&
      segments[0] == 'admin' &&
      segments[1] == 'matches' &&
      segments[3] == 'sport-management';
  final isAdminRotationRoute = segments.length == 2 &&
      segments.first == 'admin' &&
      const {
        'convocations',
        'composition',
        'guests',
        'motm',
        'waitlist',
      }.contains(segments.last);

  return isPlayerMatchRoute || isAdminMatchRoute || isAdminRotationRoute;
}

String? _safeLocalRedirect(String? value) {
  if (value == null || value.isEmpty || value.startsWith('//')) return null;

  final uri = Uri.tryParse(value);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  if (!uri.path.startsWith('/') || uri.path.startsWith('/auth')) return null;
  if (uri.path == '/matches') return '/pronos';

  return uri.toString();
}
