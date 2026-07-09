/// Utilitaires de formatage de dates et heures uniformisés pour toute l'app.
///
/// Format date : DD/MM/YY (ex. 12/07/26)
/// Format heure : 21h00
class AppFormats {
  AppFormats._();

  /// Retourne la date au format DD/MM/YY.
  static String date(DateTime dt) {
    final local = dt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = (local.year % 100).toString().padLeft(2, '0');
    return '$day/$month/$year';
  }

  /// Retourne l'heure au format 21h00.
  static String time(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${hour}h$minute';
  }

  /// Retourne date + heure : "12/07/26 • 21h00".
  static String dateTime(DateTime dt) => '${date(dt)} • ${time(dt)}';
}
