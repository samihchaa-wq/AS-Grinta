import 'dart:async';

import 'package:as_grinta/features/feature_flags/data/feature_flags_repository.dart';
import 'package:as_grinta/features/feature_flags/domain/feature_flags.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('does not call the server before authentication', () async {
    final repository = _FakeFeatureFlagsRepository();
    addTearDown(repository.dispose);
    final container = ProviderContainer(
      overrides: [
        featureFlagsRepositoryProvider.overrideWithValue(repository),
        featureFlagsSessionReadyProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    final snapshot = await container.read(
      featureFlagsControllerProvider.future,
    );

    expect(repository.fetchCount, 0);
    expect(repository.watchCount, 0);
    expect(snapshot.sourceAvailable, isFalse);
    expect(snapshot.sportsManagement.enabled, isFalse);
  });

  test('fails closed when the server flag cannot be loaded', () async {
    final repository = _FakeFeatureFlagsRepository(throwOnFetch: true);
    addTearDown(repository.dispose);
    final container = ProviderContainer(
      overrides: [
        featureFlagsRepositoryProvider.overrideWithValue(repository),
        featureFlagsSessionReadyProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);

    final snapshot = await container.read(
      featureFlagsControllerProvider.future,
    );

    expect(snapshot.sourceAvailable, isFalse);
    expect(snapshot.sportsManagement.enabled, isFalse);
    expect(repository.watchCount, 1);
    expect(container.read(sportsManagementEnabledProvider), isFalse);
  });

  test('updates the server flag and publishes the new value', () async {
    final repository = _FakeFeatureFlagsRepository();
    addTearDown(repository.dispose);
    final container = ProviderContainer(
      overrides: [
        featureFlagsRepositoryProvider.overrideWithValue(repository),
        featureFlagsSessionReadyProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);

    await container.read(featureFlagsControllerProvider.future);
    final snapshot = await container
        .read(featureFlagsControllerProvider.notifier)
        .setSportsManagementEnabled(enabled: true, justification: 'Test');

    expect(repository.lastEnabled, isTrue);
    expect(repository.lastJustification, 'Test');
    expect(snapshot.sportsManagement.enabled, isTrue);
    expect(container.read(sportsManagementEnabledProvider), isTrue);
  });

  test('refreshes a running session when the server flag changes', () async {
    final repository = _FakeFeatureFlagsRepository();
    addTearDown(repository.dispose);
    final container = ProviderContainer(
      overrides: [
        featureFlagsRepositoryProvider.overrideWithValue(repository),
        featureFlagsSessionReadyProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);

    final initial = await container.read(featureFlagsControllerProvider.future);
    expect(initial.sportsManagement.enabled, isFalse);
    expect(repository.fetchCount, 1);

    repository.publishChange(
      revision: 2,
      enabled: true,
      updatedAt: DateTime.utc(2026, 7, 20, 13),
    );
    await pumpEventQueue();

    expect(repository.fetchCount, 2);
    expect(container.read(sportsManagementEnabledProvider), isTrue);
  });

  test('ignores stale and duplicate realtime signals', () async {
    final repository = _FakeFeatureFlagsRepository();
    addTearDown(repository.dispose);
    final container = ProviderContainer(
      overrides: [
        featureFlagsRepositoryProvider.overrideWithValue(repository),
        featureFlagsSessionReadyProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);

    await container.read(featureFlagsControllerProvider.future);

    repository.publishSignal(
      revision: 1,
      updatedAt: DateTime.utc(2026, 7, 20, 11),
    );
    repository.publishSignal(
      revision: 1,
      updatedAt: DateTime.utc(2026, 7, 20, 13),
    );
    await pumpEventQueue();

    expect(repository.fetchCount, 1);
    expect(container.read(sportsManagementEnabledProvider), isFalse);
  });
}

class _FakeFeatureFlagsRepository implements FeatureFlagsRepository {
  _FakeFeatureFlagsRepository({this.throwOnFetch = false});

  final bool throwOnFetch;
  final StreamController<FeatureFlagChangeSignal> _changes =
      StreamController<FeatureFlagChangeSignal>.broadcast(sync: true);

  int fetchCount = 0;
  int watchCount = 0;
  bool? lastEnabled;
  String? lastJustification;
  bool enabled = false;
  DateTime updatedAt = DateTime.utc(2026, 7, 20, 12);

  Future<void> dispose() => _changes.close();

  void publishChange({
    required int revision,
    required bool enabled,
    required DateTime updatedAt,
  }) {
    this.enabled = enabled;
    this.updatedAt = updatedAt;
    publishSignal(revision: revision, updatedAt: updatedAt);
  }

  void publishSignal({
    required int revision,
    required DateTime updatedAt,
  }) {
    _changes.add(
      FeatureFlagChangeSignal(revision: revision, updatedAt: updatedAt),
    );
  }

  @override
  Future<FeatureFlagsSnapshot> fetchFeatureFlags() async {
    fetchCount += 1;
    if (throwOnFetch) throw StateError('unavailable');
    return _snapshot(enabled: enabled, updatedAt: updatedAt);
  }

  @override
  Stream<FeatureFlagChangeSignal> watchSportsManagementChanges() {
    watchCount += 1;
    return _changes.stream;
  }

  @override
  Future<FeatureFlagsSnapshot> setSportsManagementEnabled({
    required bool enabled,
    String? justification,
  }) async {
    lastEnabled = enabled;
    lastJustification = justification;
    this.enabled = enabled;
    updatedAt = updatedAt.add(const Duration(seconds: 1));
    return _snapshot(enabled: enabled, updatedAt: updatedAt);
  }
}

FeatureFlagsSnapshot _snapshot({
  required bool enabled,
  required DateTime updatedAt,
}) {
  return FeatureFlagsSnapshot(
    sourceAvailable: true,
    sportsManagement: SportsManagementFeature(
      enabled: enabled,
      availabilityOpenHoursBefore: 144,
      reminderHoursBefore: const [72, 24],
      usualSquadSize: 14,
      voteDurationHours: 24,
      timezone: 'Europe/Paris',
      updatedAt: updatedAt,
    ),
  );
}
