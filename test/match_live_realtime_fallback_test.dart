import 'dart:async';

import 'package:as_grinta/features/match_live/data/match_live_repository.dart';
import 'package:as_grinta/features/match_live/domain/match_live_state_bundle.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a Realtime error enables fallback and triggers a server resync',
      () async {
    final repository = _RealtimeFallbackRepository(_bundle());
    final container = ProviderContainer(
      overrides: [matchLiveRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    addTearDown(repository.dispose);

    final provider = matchLiveStateProvider('match-1');
    final subscription = container.listen(
      provider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await container.read(provider.future);
    await _flush();
    final fetchesBeforeError = repository.fetchCount;

    repository.emitError(StateError('realtime disconnected'));
    await _waitUntil(
      () => container.read(matchLiveRealtimeDegradedProvider('match-1')),
    );
    await _waitUntil(() => repository.fetchCount > fetchesBeforeError);

    expect(
      container.read(matchLiveRealtimeDegradedProvider('match-1')),
      isTrue,
    );

    repository.emitChange();
    await _waitUntil(
      () => !container.read(matchLiveRealtimeDegradedProvider('match-1')),
    );
  });

  test('the fallback polling interval stays bounded', () {
    expect(matchLiveFallbackPollInterval, const Duration(seconds: 30));
  });
}

MatchLiveStateBundle _bundle() {
  return MatchLiveStateBundle.fromRpc({
    'match_id': 'match-1',
    'session_exists': true,
    'state': 'running',
    'planned_duration_minutes': 90,
    'half': 1,
    'elapsed_seconds': 60,
    'score_as_grinta': 0,
    'score_adverse': 0,
    'exported': false,
    'lineup_revision': 1,
    'events': const [],
    'substitute_counts': const <String, int>{},
  });
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await _flush();
  }
  fail('Condition non atteinte dans le délai du test.');
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

class _RealtimeFallbackRepository implements MatchLiveRepository {
  _RealtimeFallbackRepository(this.bundle);

  final MatchLiveStateBundle bundle;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  int fetchCount = 0;

  void emitChange() => _changes.add(null);

  void emitError(Object error) => _changes.addError(error, StackTrace.current);

  void dispose() => _changes.close();

  @override
  Future<MatchLiveStateBundle> fetchLiveState(String matchId) async {
    fetchCount += 1;
    return bundle;
  }

  @override
  Stream<void> watchChanges(String matchId) => _changes.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'Unexpected repository call: ${invocation.memberName}',
    );
  }
}
