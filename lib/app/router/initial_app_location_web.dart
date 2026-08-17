import 'package:web/web.dart' as web;

String initialAppLocation() {
  final hash = web.window.location.hash;
  if (hash.startsWith('#/')) {
    final location = hash.substring(1);
    if (location.isNotEmpty) return location;
  }
  return '/matches';
}
