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

  static const _weekdaysShort = [
    'Lun',
    'Mar',
    'Mer',
    'Jeu',
    'Ven',
    'Sam',
    'Dim',
  ];

  static const _monthsShort = [
    'Janv',
    'Févr',
    'Mars',
    'Avr',
    'Mai',
    'Juin',
    'Juil',
    'Août',
    'Sept',
    'Oct',
    'Nov',
    'Déc',
  ];

  /// Jour de la semaine abrégé : "Lun", "Mar"… (DateTime.weekday va de 1 à 7).
  static String weekdayShort(DateTime dt) =>
      _weekdaysShort[dt.toLocal().weekday - 1];

  /// Mois abrégé : "Janv", "Sept"…
  static String monthShort(DateTime dt) => _monthsShort[dt.toLocal().month - 1];

  /// Numéro du jour sur deux chiffres : "07".
  static String dayNumber(DateTime dt) =>
      dt.toLocal().day.toString().padLeft(2, '0');

  /// Heure au format "20:45" (deux points, pour la colonne de date).
  static String hourMinute(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

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

  /// Cote affichée sur une base 100 : 2,00 → 200 ; 3,80 → 380.
  static String odds(double? value) =>
      value == null ? '—' : (value * 100).round().toString();
}
