const passwordRecoveryLocation = '/auth/new-password?recovery=1';

/// Paramètre de requête ajouté par `web/app_shell.js` pour forcer le
/// rechargement d'une nouvelle version : il ne fait pas partie de la route.
const _deploymentMarker = '_asg_release';

/// Route de démarrage résolue depuis l'adresse du navigateur.
class InitialBrowserLocation {
  const InitialBrowserLocation(this.location, {this.hashUrl});

  /// Route que Flutter doit monter.
  final String location;

  /// Adresse à afficher à la place de l'adresse courante (`<base>#/...`)
  /// quand celle-ci utilisait la forme chemin. `null` si rien ne change.
  final String? hashUrl;
}

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

/// Résout la route de démarrage à partir de l'adresse complète.
///
/// L'application lit ses routes après `#` (`/AS-Grinta/#/matches/…`). Mais
/// certaines adresses arrivent sous la forme chemin (`/AS-Grinta/matches/…`) :
/// anciennes notifications, lien copié, favori. GitHub Pages sert alors
/// `404.html`, copie d'`index.html`, et l'application démarrait sur le
/// calendrier. Quand la partie `#` est vide, le chemin situé sous [basePath]
/// et sa requête deviennent la route, et [InitialBrowserLocation.hashUrl]
/// donne l'adresse équivalente sous la forme `#/...`.
InitialBrowserLocation initialLocationFromBrowser({
  required String hash,
  required String pathname,
  required String search,
  required String basePath,
}) {
  if (hash.isNotEmpty && hash != '#') {
    return InitialBrowserLocation(initialLocationFromBrowserHash(hash));
  }

  final base = basePath.endsWith('/') ? basePath : '$basePath/';
  if (!pathname.startsWith(base)) {
    return const InitialBrowserLocation('/matches');
  }

  final route = pathname.substring(base.length).replaceFirst(
        RegExp(r'^/+'),
        '',
      );
  if (route.isEmpty || route == 'index.html' || route == '404.html') {
    return const InitialBrowserLocation('/matches');
  }

  final query = _withoutDeploymentMarker(search);
  final location = query.isEmpty ? '/$route' : '/$route?$query';
  return InitialBrowserLocation(location, hashUrl: '$base#$location');
}

String _withoutDeploymentMarker(String search) {
  final raw = search.startsWith('?') ? search.substring(1) : search;
  if (raw.isEmpty) return '';
  return raw
      .split('&')
      .where((part) => part.isNotEmpty)
      .where((part) => part.split('=').first != _deploymentMarker)
      .join('&');
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
