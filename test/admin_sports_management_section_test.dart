import 'package:as_grinta/features/admin/presentation/admin_sports_management_section.dart';
import 'package:as_grinta/features/feature_flags/data/feature_flags_repository.dart';
import 'package:as_grinta/features/feature_flags/domain/feature_flags.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sports management cannot be disabled from admin', (
    tester,
  ) async {
    final repository = _WidgetFeatureFlagsRepository();
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    expect(find.text('Activé en permanence'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.textContaining('Désactivé'), findsNothing);
    expect(find.textContaining('Désactiver'), findsNothing);
    expect(repository.lastEnabled, isNull);
  });
}

Widget _harness(FeatureFlagsRepository repository) {
  return ProviderScope(
    overrides: [
      featureFlagsRepositoryProvider.overrideWithValue(repository),
      featureFlagsSessionReadyProvider.overrideWithValue(true),
    ],
    child: const MaterialApp(
      home: Scaffold(body: AdminSportsManagementSection()),
    ),
  );
}

class _WidgetFeatureFlagsRepository implements FeatureFlagsRepository {
  bool? lastEnabled;

  @override
  Future<FeatureFlagsSnapshot> fetchFeatureFlags() async {
    return _snapshot();
  }

  @override
  Stream<FeatureFlagChangeSignal> watchSportsManagementChanges() {
    return const Stream<FeatureFlagChangeSignal>.empty();
  }

  @override
  Future<FeatureFlagsSnapshot> setSportsManagementEnabled({
    required bool enabled,
    String? justification,
  }) async {
    lastEnabled = enabled;
    return _snapshot();
  }
}

FeatureFlagsSnapshot _snapshot() {
  return FeatureFlagsSnapshot(
    sourceAvailable: true,
    sportsManagement: SportsManagementFeature(
      enabled: true,
      availabilityOpenHoursBefore: 144,
      reminderHoursBefore: const [72, 24],
      usualSquadSize: 14,
      voteDurationHours: 24,
      timezone: 'Europe/Paris',
      updatedAt: DateTime.utc(2026, 7, 20, 12),
    ),
  );
}
