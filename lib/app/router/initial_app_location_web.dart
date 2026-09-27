import 'package:as_grinta/app/router/initial_app_location_parser.dart';
import 'package:web/web.dart' as web;

String? _capturedInitialLocation;

void captureInitialAppLocation() {
  _capturedInitialLocation ??= _readWindowLocation();
}

String initialAppLocation() =>
    _capturedInitialLocation ?? _readWindowLocation();

String _readWindowLocation() {
  final location = web.window.location;
  final resolved = initialLocationFromBrowser(
    hash: location.hash,
    pathname: location.pathname,
    search: location.search,
    basePath: _basePath(),
  );

  final hashUrl = resolved.hashUrl;
  if (hashUrl != null) {
    // L'adresse passe sous la forme `#/...` que le routeur Flutter lit et
    // tient à jour. Rien n'est rechargé : seule la barre d'adresse change.
    try {
      web.window.history.replaceState(null, '', hashUrl);
    } catch (_) {
      // Une adresse qui ne peut pas être réécrite n'empêche pas d'ouvrir la
      // bonne page : la route a déjà été résolue.
    }
  }
  return resolved.location;
}

/// Chemin de la balise `<base href>` (`/AS-Grinta/` en production).
String _basePath() {
  final baseUri = Uri.tryParse(web.document.baseURI);
  final path = baseUri?.path ?? '/';
  return path.isEmpty ? '/' : path;
}
