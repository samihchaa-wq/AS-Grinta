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

  /// Accorde un nom en français : le pluriel n'apparaît qu'à partir de 2.
  /// Ex. : `plural(0, 'but')` → "but", `plural(1, 'but')` → "but",
  /// `plural(2, 'but')` → "buts". Utiliser [plural] pour un suffixe
  /// irrégulier (`plural(2, 'clean sheet', 'clean sheets')`).
  static String plural(int count, String singular, [String? pluralForm]) {
    if (count > 1) return pluralForm ?? '${singular}s';
    return singular;
  }

  /// Comme [plural] mais préfixé de la valeur : "0 but", "1 but", "2 buts".
  static String counted(int count, String singular, [String? pluralForm]) =>
      '$count ${plural(count, singular, pluralForm)}';

  /// Cote affichée : la valeur réelle (ex. 2,10) est montrée ×100 en entier
  /// (« 210 »). Purement cosmétique — la cote réelle utilisée pour les points
  /// n'est pas modifiée.
  static String odds(double? value) =>
      value == null ? '—' : '${(value * 100).round()}';
}
