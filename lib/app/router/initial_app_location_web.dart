import 'package:as_grinta/app/router/initial_app_location_parser.dart';
import 'package:web/web.dart' as web;

String? _capturedInitialLocation;

void captureInitialAppLocation() {
  _capturedInitialLocation ??= _readWindowLocation();
}

String initialAppLocation() =>
    _capturedInitialLocation ?? _readWindowLocation();

String _readWindowLocation() {
  return initialLocationFromBrowserHash(web.window.location.hash);
}
