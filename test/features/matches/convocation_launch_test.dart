import 'package:as_grinta/features/matches/domain/convocation_launch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('convocation launch', () {
    test('default remains J-6 at 12:00', () {
      final kickoff = DateTime(2026, 9, 20, 18, 30);
      expect(
        defaultConvocationLaunchAt(kickoff),
        DateTime(2026, 9, 14, 12),
      );
    });

    test('suggests automatic time when it is still in the future', () {
      final now = DateTime(2026, 9, 1, 10);
      final kickoff = DateTime(2026, 9, 20, 18);
      expect(
        suggestedCustomConvocationLaunchAt(kickoffAt: kickoff, now: now),
        DateTime(2026, 9, 14, 12),
      );
    });

    test('custom launch must remain before kickoff', () {
      final now = DateTime(2026, 9, 1, 10);
      final kickoff = DateTime(2026, 9, 2, 18);
      expect(
        validateConvocationLaunch(
          mode: ConvocationLaunchMode.custom,
          kickoffAt: kickoff,
          customAt: kickoff,
          now: now,
        ),
        isNotNull,
      );
    });

    test('now and automatic never require a custom timestamp', () {
      final kickoff = DateTime(2026, 9, 20, 18);
      for (final mode in [
        ConvocationLaunchMode.automatic,
        ConvocationLaunchMode.now,
      ]) {
        expect(
          validateConvocationLaunch(
            mode: mode,
            kickoffAt: kickoff,
            customAt: null,
            now: DateTime(2026, 9, 1),
          ),
          isNull,
        );
      }
    });
  });
}
