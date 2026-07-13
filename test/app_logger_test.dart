import 'package:as_grinta/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats a useful record without including the error message', () {
    const secret = 'user@example.com password=super-secret';

    final record = AppLogger.formatRecord(
      operation: 'auth sign-in',
      error: StateError(secret),
    );

    expect(record, 'operation=auth_sign-in error_type=StateError');
    expect(record, isNot(contains(secret)));
    expect(record, isNot(contains('user@example.com')));
    expect(record, isNot(contains('super-secret')));
  });
}
