import 'dart:developer' as developer;

import 'package:as_grinta/core/config/app_config.dart';
import 'package:as_grinta/core/logging/error_category.dart';

/// Enregistrement d'incident transmis au collecteur.
///
/// Ne contient jamais le message de l'erreur : seuls l'opération, le type
/// d'erreur et la référence support y figurent, exactement comme dans le
/// format texte produit par [AppLogger.formatRecord].
class AppIncident {
  const AppIncident({
    required this.reference,
    required this.operation,
    required this.errorType,
    required this.appVersion,
  });

  final String reference;
  final String operation;
  final String errorType;
  final String appVersion;
}

abstract final class AppLogger {
  static int _sequence = 0;

  /// Collecteur d'incidents, branché sur Supabase au démarrage.
  ///
  /// Sans lui, `dart:developer.log()` est le seul point de sortie — et il
  /// n'émet rien dans un build web release : la référence affichée à
  /// l'utilisateur (« Référence : ASG-… ») n'existait alors nulle part
  /// ailleurs, et la procédure de support décrite dans `docs/observability.md`
  /// était inopérante.
  static void Function(AppIncident incident)? sink;

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
      error: describeErrorForIncident(error),
      stackTrace: stackTrace,
    );

    // Le collecteur ne doit jamais faire échouer la journalisation : une
    // exception ici serait captée par le gestionnaire global, qui rappellerait
    // AppLogger.error, et ainsi de suite.
    try {
      sink?.call(
        AppIncident(
          reference: incidentReference,
          operation: sanitizeOperation(operation),
          errorType: describeErrorForIncident(error),
          appVersion: AppConfig.version,
        ),
      );
    } catch (_) {
      // Ignoré volontairement.
    }

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
    return 'ASG-$date-$time-${three(_sequence)}';
  }

  /// Normalise un nom d'opération pour qu'il reste inoffensif en journal.
  static String sanitizeOperation(String operation) =>
      operation.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');

  static String formatRecord({
    required String operation,
    required Object error,
    String? incidentReference,
  }) {
    final safeOperation = sanitizeOperation(operation);
    final reference = incidentReference == null
        ? ''
        : ' incident=$incidentReference version=${AppConfig.version}';
    final errorType = describeErrorForIncident(error);
    return 'operation=$safeOperation error_type=$errorType$reference';
  }
}
