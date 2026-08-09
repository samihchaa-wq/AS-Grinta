import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('temporary profile failure keeps the active session path', () {
    final authState = File(
      'lib/features/auth/presentation/auth_state.dart',
    ).readAsStringSync();
    final loadingPage = File(
      'lib/features/auth/presentation/auth_loading_page.dart',
    ).readAsStringSync();

    expect(authState, contains('hasSession'));
    expect(authState, contains('Connexion temporairement indisponible'));
    expect(loadingPage, contains('Ta session est toujours active'));
    expect(loadingPage, contains("label: const Text('Réessayer')"));
  });

  test('event writes invalidate persistent and memory caches', () {
    final source = File(
      'lib/features/matches/data/club_events_repository.dart',
    ).readAsStringSync();

    expect(source, contains('_invalidateCache'));
    expect(source, contains('remove(_persistentKey)'));
  });

  test('match writes force a fresh generation', () {
    final source = File(
      'lib/features/matches/presentation/matches_controller.dart',
    ).readAsStringSync();

    expect(source, contains('forceRefresh: true'));
    expect(source, contains('_loadGeneration'));
  });
}
