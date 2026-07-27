import 'package:as_grinta/features/feature_flags/data/feature_flags_repository.dart';
import 'package:as_grinta/features/feature_flags/domain/feature_flags.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('does not call the server before authentication', () async {
    final repository = _FakeFeatureFlagsRepository();
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
    expect(snapshot.sourceAvailable, isFalse);
    expect(snapshot.sportsManagement.enabled, isFalse);
  });

  test('fails closed when the server flag cannot be loaded', () async {
    final container = ProviderContainer(
      overrides: [
        featureFlagsRepositoryProvider.overrideWithValue(
          _FakeFeatureFlagsRepository(throwOnFetch: true),
        ),
        featureFlagsSessionReadyProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);

    final snapshot = await container.read(
      featureFlagsControllerProvider.future,
    );

    expect(snapshot.sourceAvailable, isFalse);
    expect(snapshot.sportsManagement.enabled, isFalse);
    expect(container.read(sportsManagementEnabledProvider), isFalse);
  });

  test('updates the server flag and publishes the new value', () async {
    final repository = _FakeFeatureFlagsRepository();
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

  test('reloads the server value after a lifecycle invalidation', () async {
    final repository = _FakeFeatureFlagsRepository(
      fetchValues: const [false, true],
    );
    final container = ProviderContainer(
      overrides: [
        featureFlagsRepositoryProvider.overrideWithValue(repository),
        featureFlagsSessionReadyProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);

    final initial = await container.read(featureFlagsControllerProvider.future);
    expect(initial.sportsManagement.enabled, isFalse);

    // AsGrintaApp invalide le provider au retour au premier plan et après un
    // changement d’authentification. L’invalidation doit relire le serveur.
    container.invalidate(featureFlagsControllerProvider);
    final refreshed =
        await container.read(featureFlagsControllerProvider.future);

    expect(refreshed.sportsManagement.enabled, isTrue);
    expect(repository.fetchCount, 2);
  });

  test('restores the previous value when an admin update fails', () async {
    final repository = _FakeFeatureFlagsRepository(
      fetchValues: const [true],
      throwOnSet: true,
    );
    final container = ProviderContainer(
      overrides: [
        featureFlagsRepositoryProvider.overrideWithValue(repository),
        featureFlagsSessionReadyProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);

    await container.read(featureFlagsControllerProvider.future);

    await expectLater(
      container
          .read(featureFlagsControllerProvider.notifier)
          .setSportsManagementEnabled(enabled: false),
      throwsStateError,
    );
    expect(container.read(sportsManagementEnabledProvider), isTrue);
  });
}

class _FakeFeatureFlagsRepository implements FeatureFlagsRepository {
  _FakeFeatureFlagsRepository({
    this.throwOnFetch = false,
    this.throwOnSet = false,
    this.fetchValues = const [false],
  });

  final bool throwOnFetch;
  final bool throwOnSet;
  final List<bool> fetchValues;
  int fetchCount = 0;
  bool? lastEnabled;
  String? lastJustification;

  @override
  Future<FeatureFlagsSnapshot> fetchFeatureFlags() async {
    fetchCount += 1;
    if (throwOnFetch) throw StateError('unavailable');
    final index = (fetchCount - 1).clamp(0, fetchValues.length - 1);
    return _snapshot(enabled: fetchValues[index]);
  }

  @override
  Future<FeatureFlagsSnapshot> setSportsManagementEnabled({
    required bool enabled,
    String? justification,
  }) async {
    if (throwOnSet) throw StateError('unavailable');
    lastEnabled = enabled;
    lastJustification = justification;
    return _snapshot(enabled: enabled);
  }
}

FeatureFlagsSnapshot _snapshot({required bool enabled}) {
  return FeatureFlagsSnapshot(
    sourceAvailable: true,
    sportsManagement: SportsManagementFeature(
      enabled: enabled,
      availabilityOpenHoursBefore: 144,
      reminderHoursBefore: const [72, 24],
      usualSquadSize: 14,
      voteDurationHours: 24,
      timezone: 'Europe/Paris',
      updatedAt: DateTime.utc(2026, 7, 20, 12),
    ),
  );
}
