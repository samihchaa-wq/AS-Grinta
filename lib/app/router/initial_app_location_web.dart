import 'package:web/web.dart' as web;

String? _capturedInitialLocation;

void captureInitialAppLocation() {
  _capturedInitialLocation ??= _readWindowLocation();
}

String initialAppLocation() =>
    _capturedInitialLocation ?? _readWindowLocation();

String _readWindowLocation() {
  final hash = web.window.location.hash;

  // Le flux de récupération Supabase utilise lui aussi le fragment URL.
  // Il doit donc être reconnu avant le routage Flutter en #/... : sinon la
  // destination de changement de mot de passe est perdue au démarrage.
  if (_isPasswordRecoveryHash(hash)) {
    return '/auth/new-password?recovery=1';
  }

  if (hash.startsWith('#/')) {
    final location = hash.substring(1);
    if (location.isNotEmpty) return location;
  }
  return '/matches';
}

bool _isPasswordRecoveryHash(String hash) {
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
