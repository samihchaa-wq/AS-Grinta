import 'package:as_grinta/features/admin/presentation/admin_sports_management_section.dart';
import 'package:as_grinta/features/feature_flags/data/feature_flags_repository.dart';
import 'package:as_grinta/features/feature_flags/domain/feature_flags.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an administrator can enable the module', (tester) async {
    final repository = _WidgetFeatureFlagsRepository(initialEnabled: false);
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    expect(find.text('Désactivé'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(repository.lastEnabled, isTrue);
    expect(find.text('Activé'), findsOneWidget);
  });

  testWidgets('disabling requires confirmation and preserves the reason',
      (tester) async {
    final repository = _WidgetFeatureFlagsRepository(initialEnabled: true);
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Désactiver le module ?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Retour au mode historique');
    await tester.tap(find.widgetWithText(FilledButton, 'Désactiver'));
    await tester.pumpAndSettle();

    expect(repository.lastEnabled, isFalse);
    expect(repository.lastJustification, 'Retour au mode historique');
    expect(find.text('Désactivé'), findsOneWidget);
  });
}

Widget _harness(FeatureFlagsRepository repository) {
  return ProviderScope(
    overrides: [
      featureFlagsRepositoryProvider.overrideWithValue(repository),
      featureFlagsSessionReadyProvider.overrideWithValue(true),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: AdminSportsManagementSection(),
      ),
    ),
  );
}

class _WidgetFeatureFlagsRepository implements FeatureFlagsRepository {
  _WidgetFeatureFlagsRepository({required this.initialEnabled});

  final bool initialEnabled;
  bool? lastEnabled;
  String? lastJustification;

  @override
  Future<FeatureFlagsSnapshot> fetchFeatureFlags() async {
    return _snapshot(initialEnabled);
  }

  @override
  Future<FeatureFlagsSnapshot> setSportsManagementEnabled({
    required bool enabled,
    String? justification,
  }) async {
    lastEnabled = enabled;
    lastJustification = justification;
    return _snapshot(enabled);
  }
}

FeatureFlagsSnapshot _snapshot(bool enabled) {
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
