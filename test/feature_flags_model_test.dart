import 'package:as_grinta/features/feature_flags/domain/feature_flags.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FeatureFlagsSnapshot', () {
    test('parses the sports-management server configuration', () {
      final snapshot = FeatureFlagsSnapshot.fromRpc({
        'sports_management': {
          'enabled': true,
          'updated_at': '2026-07-20T12:00:00Z',
          'config': {
            'availability_open_hours_before': 144,
            'reminder_hours_before': [72, 24],
            'usual_squad_size': 14,
            'vote_duration_hours': 24,
            'timezone': 'Europe/Paris',
          },
        },
      });

      expect(snapshot.sourceAvailable, isTrue);
      expect(snapshot.sportsManagement.enabled, isTrue);
      expect(snapshot.sportsManagement.availabilityOpenHoursBefore, 144);
      expect(snapshot.sportsManagement.reminderHoursBefore, [72, 24]);
      expect(snapshot.sportsManagement.usualSquadSize, 14);
      expect(snapshot.sportsManagement.voteDurationHours, 24);
      expect(snapshot.sportsManagement.timezone, 'Europe/Paris');
      expect(snapshot.sportsManagement.updatedAt, isNotNull);
    });

    test('uses safe defaults for malformed optional configuration', () {
      final snapshot = FeatureFlagsSnapshot.fromRpc({
        'sports_management': {
          'enabled': false,
          'config': {
            'availability_open_hours_before': -1,
            'reminder_hours_before': [],
            'usual_squad_size': 'invalid',
            'vote_duration_hours': 0,
            'timezone': '',
          },
        },
      });

      final feature = snapshot.sportsManagement;
      expect(feature.enabled, isFalse);
      expect(feature.availabilityOpenHoursBefore, 144);
      expect(feature.reminderHoursBefore, [72, 24]);
      expect(feature.usualSquadSize, 14);
      expect(feature.voteDurationHours, 24);
      expect(feature.timezone, 'Europe/Paris');
    });

    test('rejects a response without the expected feature', () {
      expect(
        () => FeatureFlagsSnapshot.fromRpc({'other_feature': {}}),
        throwsFormatException,
      );
    });

    test('unavailable snapshot always fails closed', () {
      const snapshot = FeatureFlagsSnapshot.unavailable();

      expect(snapshot.sourceAvailable, isFalse);
      expect(snapshot.sportsManagement.enabled, isFalse);
    });
  });
}
