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
}

class _FakeFeatureFlagsRepository implements FeatureFlagsRepository {
  _FakeFeatureFlagsRepository({this.throwOnFetch = false});

  final bool throwOnFetch;
  int fetchCount = 0;
  bool? lastEnabled;
  String? lastJustification;

  @override
  Future<FeatureFlagsSnapshot> fetchFeatureFlags() async {
    fetchCount += 1;
    if (throwOnFetch) throw StateError('unavailable');
    return _snapshot(enabled: false);
  }

  @override
  Future<FeatureFlagsSnapshot> setSportsManagementEnabled({
    required bool enabled,
    String? justification,
  }) async {
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
