import 'dart:js_interop';

@JS('window.location.hash')
external JSString get _windowLocationHash;

String initialAppLocation() {
  final hash = _windowLocationHash.toDart;
  if (hash.startsWith('#/')) {
    final location = hash.substring(1);
    if (location.isNotEmpty) return location;
  }
  return '/matches';
}
