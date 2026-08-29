import 'package:as_grinta/app/shell/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldRefocusMatchesAfterRouteReturn', () {
    test('preserves position after a modern past-match detail', () {
      expect(
        shouldRefocusMatchesAfterRouteReturn(
          previousLocationPath: '/matches/match-123',
          currentLocationPath: '/matches',
        ),
        isFalse,
      );
    });

    test('preserves position after an imported historical match detail', () {
      expect(
        shouldRefocusMatchesAfterRouteReturn(
          previousLocationPath: '/matches/history/history-123',
          currentLocationPath: '/matches',
        ),
        isFalse,
      );
    });

    test('keeps refocus for other same-branch returns', () {
      expect(
        shouldRefocusMatchesAfterRouteReturn(
          previousLocationPath: '/profile',
          currentLocationPath: '/matches',
        ),
        isTrue,
      );
      expect(
        shouldRefocusMatchesAfterRouteReturn(
          previousLocationPath: '/admin',
          currentLocationPath: '/matches',
        ),
        isTrue,
      );
    });

    test('does not refocus without a return to the calendar root', () {
      expect(
        shouldRefocusMatchesAfterRouteReturn(
          previousLocationPath: '/matches',
          currentLocationPath: '/matches',
        ),
        isFalse,
      );
      expect(
        shouldRefocusMatchesAfterRouteReturn(
          previousLocationPath: '/profile',
          currentLocationPath: '/stats',
        ),
        isFalse,
      );
    });
  });
}
