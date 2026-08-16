import 'dart:async';

import 'package:as_grinta/features/match_live/data/match_live_repository.dart';
import 'package:as_grinta/features/match_live/domain/match_live_state_bundle.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an older Live refresh cannot overwrite a newer snapshot', () async {
    final repository = _ControlledMatchLiveRepository(_bundle(score: 0));
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

    // build() fait volontairement une relecture juste après avoir installé
    // Realtime afin de fermer la fenêtre fetch -> abonnement.
    await _waitUntil(() => repository.pendingFetches.length == 1);
    repository.pendingFetches.removeAt(0).complete(_bundle(score: 0));
    await _flush();

    repository.emitChange();
    await _waitUntil(() => repository.pendingFetches.length == 1);
    final older = repository.pendingFetches.removeAt(0);

    repository.emitChange();
    await _waitUntil(() => repository.pendingFetches.length == 1);
    final newer = repository.pendingFetches.removeAt(0);

    newer.complete(_bundle(score: 2));
    await _flush();
    expect(container.read(provider).value?.session.scoreAsGrinta, 2);

    older.complete(_bundle(score: 1));
    await _flush();

    expect(
      container.read(provider).value?.session.scoreAsGrinta,
      2,
      reason: 'la réponse plus ancienne ne doit jamais remettre le Live à 1-0',
    );
  });

  test(
    'a failed mutation reloads authoritative state before reporting it',
    () async {
      final repository = _ControlledMatchLiveRepository(
        _bundle(score: 0),
        scoreMutationErrors: [
          StateError('network response lost'),
          StateError('retry also failed'),
        ],
      );
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
      final messageSubscription = container.listen(
        matchLiveActionMessageProvider('match-1'),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(messageSubscription.close);

      await container.read(provider.future);
      await _waitUntil(() => repository.pendingFetches.length == 1);
      repository.pendingFetches.removeAt(0).complete(_bundle(score: 0));
      await _flush();

      final mutation =
          container.read(provider.notifier).adjustScore(team: 'us', delta: 1);

      await _waitUntil(() => repository.pendingFetches.length == 1);
      repository.pendingFetches.removeAt(0).complete(_bundle(score: 1));

      await expectLater(mutation, throwsA(isA<StateError>()));
      expect(container.read(provider).value?.session.scoreAsGrinta, 1);
      expect(
        container.read(matchLiveActionMessageProvider('match-1')),
        contains('Action non confirmée'),
      );
    },
  );

  test('a lost score response retries with the exact same operation id', () async {
    final repository = _ControlledMatchLiveRepository(
      _bundle(score: 0),
      scoreMutationErrors: [StateError('network response lost after commit')],
      scoreMutationResult: _bundle(score: 1),
    );
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
    await _waitUntil(() => repository.pendingFetches.length == 1);
    repository.pendingFetches.removeAt(0).complete(_bundle(score: 0));
    await _flush();

    await container.read(provider.notifier).adjustScore(team: 'us', delta: 1);

    expect(repository.scoreOperationIds, hasLength(2));
    expect(repository.scoreOperationIds[1], repository.scoreOperationIds[0]);
    expect(
      repository.scoreOperationIds.first,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(container.read(provider).value?.session.scoreAsGrinta, 1);
  });

  test('saveLiveLineup forwards the rendered lineup revision', () async {
    final repository = _ControlledMatchLiveRepository(_bundle(score: 0));
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
    await _waitUntil(() => repository.pendingFetches.length == 1);
    repository.pendingFetches.removeAt(0).complete(_bundle(score: 0));
    await _flush();

    await container.read(provider.notifier).saveLiveLineup(
      entries: const [],
      expectedLineupRevision: 42,
    );

    expect(repository.lastExpectedLineupRevision, 42);
  });
}

MatchLiveStateBundle _bundle({required int score}) {
  return MatchLiveStateBundle.fromRpc({
    'match_id': 'match-1',
    'session_exists': true,
    'state': 'running',
    'planned_duration_minutes': 90,
    'half': 1,
    'elapsed_seconds': 60,
    'score_as_grinta': score,
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

class _ControlledMatchLiveRepository implements MatchLiveRepository {
  _ControlledMatchLiveRepository(
    this.initial, {
    List<Object>? scoreMutationErrors,
    this.scoreMutationResult,
  }) : scoreMutationErrors = List<Object>.of(scoreMutationErrors ?? const []);

  final MatchLiveStateBundle initial;
  final MatchLiveStateBundle? scoreMutationResult;
  final List<Object> scoreMutationErrors;
  final List<String> scoreOperationIds = [];
  final StreamController<void> _changes = StreamController<void>.broadcast();
  final List<Completer<MatchLiveStateBundle>> pendingFetches = [];
  int? lastExpectedLineupRevision;
  var _fetchCount = 0;

  void emitChange() => _changes.add(null);

  void dispose() => _changes.close();

  @override
  Future<MatchLiveStateBundle> fetchLiveState(String matchId) {
    if (_fetchCount++ == 0) return Future.value(initial);
    final completer = Completer<MatchLiveStateBundle>();
    pendingFetches.add(completer);
    return completer.future;
  }

  @override
  Future<MatchLiveStateBundle> adjustScore({
    required String matchId,
    required String team,
    required int delta,
    required String operationId,
    String? scorerParticipantId,
  }) async {
    scoreOperationIds.add(operationId);
    if (scoreMutationErrors.isNotEmpty) {
      throw scoreMutationErrors.removeAt(0);
    }
    return scoreMutationResult ?? initial;
  }

  @override
  Future<MatchLiveStateBundle> saveLiveLineup({
    required String matchId,
    required List<Map<String, dynamic>> entries,
    required int expectedLineupRevision,
    List<({String playerIn, String playerOut})> substitutions = const [],
  }) async {
    lastExpectedLineupRevision = expectedLineupRevision;
    return initial;
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
