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
    return _loadingRedirect(uri, location);
  }

  // Un compte nouvellement inscrit garde sa session mais reste uniquement sur
  // l'écran d'attente. Dès que le profil passe active, le refresh du routeur
  // le fait entrer normalement dans l'application.
  final isPending = authState.profile?.isPending == true;
  if (isPending) {
    return location == '/auth/loading' ? null : '/auth/loading';
  }

  // Une session encore valide ne doit jamais être présentée comme une vraie
  // déconnexion simplement parce que le profil ne répond pas momentanément.
  final profileUnavailable = authState.hasSession &&
      authState.profile == null &&
      authState.error != null;
  if (profileUnavailable) {
    return _loadingRedirect(uri, location);
  }

  if (location == '/auth/loading') {
    // L'écran de chargement a mémorisé la destination initiale : un lien de
    // réinitialisation ou d'inscription ouvert à froid doit y revenir, pas
    // retomber sur la connexion.
    final pending = _pendingDestination(uri.queryParameters['redirect']);
    if (pending != null) {
      if (_isRecoveryDestination(pending)) return pending;
      if (!authState.isAuthenticated &&
          _isSignedOutAuthDestination(pending)) {
        return pending;
      }
    }
    if (!authState.isAuthenticated) {
      return pending == null
          ? '/auth/sign-in'
          : '/auth/sign-in?redirect=${Uri.encodeComponent(pending)}';
    }
  }

  final isPasswordChangeRoute = location == '/auth/new-password';
  final isRecoveryRoute =
      isPasswordChangeRoute && uri.queryParameters['recovery'] == '1';
  final mustChangePassword = authState.profile?.mustChangePassword == true;

  if (authState.isAuthenticated && mustChangePassword) {
    return isPasswordChangeRoute ? null : '/auth/new-password';
  }
  if (isPasswordChangeRoute && !mustChangePassword && !isRecoveryRoute) {
    return '/matches';
  }

  final isAuthRoute = location.startsWith('/auth');
  if (!authState.isAuthenticated && !isAuthRoute && location != '/') {
    return '/auth/sign-in?redirect=${Uri.encodeComponent(uri.toString())}';
  }

  if (authState.isAuthenticated && isAuthRoute && !isRecoveryRoute) {
    final redirect = _safeLocalRedirect(uri.queryParameters['redirect']);
    return redirect ?? '/matches';
  }

  if (location == '/' || location == '/home' || location == '/accueil') {
    return '/matches';
  }

  if (_isSportsManagementRoute(uri) && !sportsManagementEnabled) {
    final segments =
        uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (segments.length == 3 &&
        segments[0] == 'matches' &&
        segments[2] == 'lineup') {
      return '/matches/${segments[1]}/prediction';
    }
    return '/matches';
  }

  final role = authState.profile?.role;
  final isAdmin = role?.isAdmin == true;
  final segments =
      uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
  final isFinalizationRoute =
      location.startsWith('/matches/') && location.endsWith('/finalize');
  final isAdminRoute = location == '/admin' || location.startsWith('/admin/');
  final isMatchAdminRoute = segments.length == 3 &&
      segments.first == 'matches' &&
      const {'composition', 'guests'}.contains(segments.last);
  final isPlayersRoute = location == '/players';

  if (isFinalizationRoute && !isAdmin) return '/matches';
  if ((isAdminRoute || isMatchAdminRoute || isPlayersRoute) && !isAdmin) {
    return '/matches';
  }
  return null;
}

/// Redirige vers l'écran de chargement en emportant la destination demandée.
///
/// Sans ce report, un démarrage à froid (lien de réinitialisation, favori,
/// partage) perd la route et sa query string : l'utilisateur atterrit sur la
/// connexion sans jamais voir l'écran qu'il avait demandé.
String? _loadingRedirect(Uri uri, String location) {
  if (location == '/auth/loading') return null;

  final destination = _preservableDestination(uri, location);
  if (destination == null) return '/auth/loading';
  return '/auth/loading?redirect=${Uri.encodeComponent(destination)}';
}

String? _preservableDestination(Uri uri, String location) {
  if (location == '/' || location == '/home' || location == '/accueil') {
    return null;
  }

  final isRecoveryRoute = location == '/auth/new-password' &&
      uri.queryParameters['recovery'] == '1';
  final isSignedOutAuthRoute = location == '/auth/register';
  if (location.startsWith('/auth') &&
      !isRecoveryRoute &&
      !isSignedOutAuthRoute) {
    return null;
  }

  return uri.toString();
}

String? _pendingDestination(String? value) {
  if (value == null || value.isEmpty || value.startsWith('//')) return null;

  final uri = Uri.tryParse(value);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  if (!uri.path.startsWith('/') || uri.path == '/auth/loading') return null;

  return uri.toString();
}

bool _isRecoveryDestination(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.path == '/auth/new-password' &&
      uri.queryParameters['recovery'] == '1';
}

bool _isSignedOutAuthDestination(String value) {
  final uri = Uri.tryParse(value);
  return uri != null && uri.path == '/auth/register';
}

bool _isSportsManagementRoute(Uri uri) {
  final segments =
      uri.pathSegments.where((segment) => segment.isNotEmpty).toList();

  final isPlayerMatchRoute = segments.length == 3 &&
      segments.first == 'matches' &&
      const {
        'availability',
        'lineup',
        'vote',
        'composition',
        'guests',
      }.contains(segments.last);
  final isAdminMatchRoute = segments.length == 4 &&
      segments[0] == 'admin' &&
      segments[1] == 'matches' &&
      segments[3] == 'sport-management';
  final isAdminRotationRoute = segments.length == 2 &&
      segments.first == 'admin' &&
      const {
        'composition',
        'guests',
        'motm',
        'waitlist',
      }.contains(segments.last);
  final isPlayerWaitlistRoute =
      segments.length == 1 && segments.first == 'waitlist';

  return isPlayerMatchRoute ||
      isAdminMatchRoute ||
      isAdminRotationRoute ||
      isPlayerWaitlistRoute;
}

String? _safeLocalRedirect(String? value) {
  if (value == null || value.isEmpty || value.startsWith('//')) return null;

  final uri = Uri.tryParse(value);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  if (!uri.path.startsWith('/') || uri.path.startsWith('/auth')) return null;
  if (uri.path == '/accueil' || uri.path == '/home') return '/matches';
  if (uri.path == '/pronos' && uri.queryParameters['category'] == 'matches') {
    return '/matches';
  }

  return uri.toString();
}
