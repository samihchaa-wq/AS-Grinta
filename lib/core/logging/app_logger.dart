import 'dart:developer' as developer;

abstract final class AppLogger {
  static void error(String operation, Object error, [StackTrace? stackTrace]) {
    developer.log(
      formatRecord(operation: operation, error: error),
      name: 'as_grinta',
      level: 1000,
      error: error.runtimeType,
      stackTrace: stackTrace,
    );
  }

  static String formatRecord({
    required String operation,
    required Object error,
  }) {
    final safeOperation = operation.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    return 'operation=$safeOperation error_type=${error.runtimeType}';
  }
}
