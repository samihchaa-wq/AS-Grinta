import 'package:as_grinta/app/router/initial_app_location_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('initialLocationFromBrowserHash', () {
    test('keeps a regular Flutter hash route', () {
      expect(
        initialLocationFromBrowserHash('#/matches/123?tab=details'),
        '/matches/123?tab=details',
      );
    });

    test('sends a successful recovery fragment to the password screen', () {
      expect(
        initialLocationFromBrowserHash('#type=recovery&expires_in=3600'),
        passwordRecoveryLocation,
      );
    });

    test('does not treat a failed recovery fragment as successful', () {
      expect(
        initialLocationFromBrowserHash(
          '#type=recovery&error=access_denied&error_code=otp_expired',
        ),
        '/matches',
      );
    });

    test('defaults to matches when the hash is unrelated', () {
      expect(initialLocationFromBrowserHash('#foo=bar'), '/matches');
      expect(initialLocationFromBrowserHash(''), '/matches');
    });
  });
}
