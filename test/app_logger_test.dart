import 'package:as_grinta/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats a useful record without including the error message', () {
    const secret = 'user@example.com password=super-secret';

    final record = AppLogger.formatRecord(
      operation: 'auth sign-in',
      error: StateError(secret),
      incidentReference: 'MPG-20260727-120000-001',
    );

    expect(record, contains('operation=auth_sign-in'));
    expect(record, contains('error_type=StateError'));
    expect(record, contains('incident=MPG-20260727-120000-001'));
    expect(record, contains('version='));
    expect(record, isNot(contains(secret)));
    expect(record, isNot(contains('user@example.com')));
    expect(record, isNot(contains('super-secret')));
  });

  test('creates a short support reference without personal data', () {
    final reference = AppLogger.createIncidentReference(
      at: DateTime.utc(2026, 7, 27, 12, 34, 56),
    );

    expect(reference, matches(RegExp(r'^MPG-20260727-123456-\d{3}$')));
  });
}
