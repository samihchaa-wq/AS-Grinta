import 'dart:developer' as developer;

import 'package:as_grinta/core/config/app_config.dart';

abstract final class AppLogger {
  static int _sequence = 0;

  /// Journalise une erreur sans inclure son message potentiellement sensible et
  /// renvoie une référence courte pouvant être communiquée au support.
  static String error(
    String operation,
    Object error, [
    StackTrace? stackTrace,
  ]) {
    final incidentReference = createIncidentReference();
    developer.log(
      formatRecord(
        operation: operation,
        error: error,
        incidentReference: incidentReference,
      ),
      name: 'as_grinta',
      level: 1000,
      error: error.runtimeType,
      stackTrace: stackTrace,
    );
    return incidentReference;
  }

  static String createIncidentReference({DateTime? at}) {
    final instant = (at ?? DateTime.now()).toUtc();
    _sequence = (_sequence + 1) % 1000;
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    final date = '${instant.year}${two(instant.month)}${two(instant.day)}';
    final time =
        '${two(instant.hour)}${two(instant.minute)}${two(instant.second)}';
    return 'MPG-$date-$time-${three(_sequence)}';
  }

  static String formatRecord({
    required String operation,
    required Object error,
    String? incidentReference,
  }) {
    final safeOperation = operation.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    final reference = incidentReference == null
        ? ''
        : ' incident=$incidentReference version=${AppConfig.version}';
    return 'operation=$safeOperation error_type=${error.runtimeType}$reference';
  }
}
