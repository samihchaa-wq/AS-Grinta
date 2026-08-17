import 'package:web/web.dart' as web;

String? _capturedInitialLocation;

void captureInitialAppLocation() {
  _capturedInitialLocation ??= _readWindowLocation();
}

String initialAppLocation() =>
    _capturedInitialLocation ?? _readWindowLocation();

String _readWindowLocation() {
  final hash = web.window.location.hash;
  if (hash.startsWith('#/')) {
    final location = hash.substring(1);
    if (location.isNotEmpty) return location;
  }
  return '/matches';
}
