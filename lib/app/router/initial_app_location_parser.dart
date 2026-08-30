const passwordRecoveryLocation = '/auth/new-password?recovery=1';

/// Resolves the route Flutter should mount from the browser hash captured
/// before Supabase initialization.
String initialLocationFromBrowserHash(String hash) {
  if (_isSuccessfulPasswordRecoveryHash(hash)) {
    return passwordRecoveryLocation;
  }

  if (hash.startsWith('#/')) {
    final location = hash.substring(1);
    if (location.isNotEmpty) return location;
  }

  return '/matches';
}

bool _isSuccessfulPasswordRecoveryHash(String hash) {
  if (!hash.startsWith('#') || hash.startsWith('#/') || hash.length == 1) {
    return false;
  }

  try {
    final parameters = Uri(query: hash.substring(1)).queryParameters;
    return parameters['type'] == 'recovery' && !parameters.containsKey('error');
  } on FormatException {
    return false;
  }
}
