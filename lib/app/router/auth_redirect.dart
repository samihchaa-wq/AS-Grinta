import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';

String? resolveAuthRedirect({
  required AuthState authState,
  required Uri uri,
  required String matchedLocation,
}) {
  final location = matchedLocation;

  if (authState.isLoading) {
    return location == '/auth/loading' ? null : '/auth/loading';
  }

  final isPasswordChangeRoute = location == '/auth/new-password';
  final mustChangePassword = authState.profile?.mustChangePassword == true;

  if (authState.isAuthenticated && mustChangePassword) {
    return isPasswordChangeRoute ? null : '/auth/new-password';
  }
  if (isPasswordChangeRoute && !mustChangePassword) return '/matches';

  final isAuthRoute = location.startsWith('/auth');
  if (!authState.isAuthenticated && !isAuthRoute && location != '/') {
    return '/auth/sign-in?redirect=${Uri.encodeComponent(uri.toString())}';
  }

  if (authState.isAuthenticated && isAuthRoute) {
    final redirect = _safeLocalRedirect(uri.queryParameters['redirect']);
    return redirect ?? '/matches';
  }

  if (location == '/' || location == '/home') return '/matches';

  final role = authState.profile?.role;
  final isAdmin = role == AuthRole.admin;
  final isStaff = role?.isStaff == true;
  final isFinalizationRoute =
      location.startsWith('/matches/') && location.endsWith('/finalize');
  final isAdminRoute = location == '/admin';
  final isPlayersRoute = location == '/players';

  if (isFinalizationRoute && !isAdmin) return '/matches';
  if (isAdminRoute && !isStaff) return '/matches';
  if (isPlayersRoute && !isStaff) return '/matches';
  return null;
}

String? _safeLocalRedirect(String? value) {
  if (value == null || value.isEmpty || value.startsWith('//')) return null;

  final uri = Uri.tryParse(value);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  if (!uri.path.startsWith('/') || uri.path.startsWith('/auth')) return null;

  return uri.toString();
}
