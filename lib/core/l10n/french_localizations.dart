import 'package:as_grinta/core/l10n/french_date_data.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_custom.dart' as intl_data;
import 'package:intl/intl.dart' as intl;

/// Traductions de Flutter (calendriers, boutons, sélecteurs de date…) pour
/// le seul français.
///
/// Les délégués `GlobalMaterialLocalizations.delegate`,
/// `GlobalCupertinoLocalizations.delegate` et
/// `GlobalWidgetsLocalizations.delegate` choisissent la langue au moment du
/// lancement : ils embarquent donc dans le programme les textes et formats de
/// date de plus de quatre-vingts langues, environ 350 Ko téléchargés et lus
/// par chaque joueur. L'application n'existe qu'en français : ces délégués
/// construisent directement les classes françaises de Flutter, avec
/// exactement les mêmes formats (voir french_localizations_test.dart).
const List<LocalizationsDelegate<dynamic>> frenchLocalizationsDelegates = [
  _FrenchMaterialLocalizationsDelegate(),
  _FrenchWidgetsLocalizationsDelegate(),
  _FrenchCupertinoLocalizationsDelegate(),
];

const String _locale = 'fr';
bool _dateDataReady = false;

/// Charge une seule fois les noms de jours, de mois et les formats français.
void _ensureFrenchDateData() {
  if (_dateDataReady) return;
  intl_data.initializeDateFormattingCustom(
    locale: _locale,
    symbols: frenchDateSymbols,
    patterns: frenchDatePatterns,
  );
  _dateDataReady = true;
}

class _FrenchMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _FrenchMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == _locale;

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    _ensureFrenchDateData();
    return SynchronousFuture<MaterialLocalizations>(
      MaterialLocalizationFr(
        fullYearFormat: intl.DateFormat.y(_locale),
        compactDateFormat: intl.DateFormat.yMd(_locale),
        shortDateFormat: intl.DateFormat.yMMMd(_locale),
        mediumDateFormat: intl.DateFormat.MMMEd(_locale),
        longDateFormat: intl.DateFormat.yMMMMEEEEd(_locale),
        yearMonthFormat: intl.DateFormat.yMMMM(_locale),
        shortMonthDayFormat: intl.DateFormat.MMMd(_locale),
        decimalFormat: intl.NumberFormat.decimalPattern(_locale),
        twoDigitZeroPaddedFormat: intl.NumberFormat('00', _locale),
      ),
    );
  }

  @override
  bool shouldReload(_FrenchMaterialLocalizationsDelegate old) => false;
}

class _FrenchCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _FrenchCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == _locale;

  @override
  Future<CupertinoLocalizations> load(Locale locale) {
    _ensureFrenchDateData();
    return SynchronousFuture<CupertinoLocalizations>(
      CupertinoLocalizationFr(
        fullYearFormat: intl.DateFormat.y(_locale),
        dayFormat: intl.DateFormat.d(_locale),
        weekdayFormat: intl.DateFormat.E(_locale),
        mediumDateFormat: intl.DateFormat.MMMEd(_locale),
        singleDigitHourFormat: intl.DateFormat('HH', _locale),
        singleDigitMinuteFormat: intl.DateFormat.m(_locale),
        doubleDigitMinuteFormat: intl.DateFormat('mm', _locale),
        singleDigitSecondFormat: intl.DateFormat.s(_locale),
        decimalFormat: intl.NumberFormat.decimalPattern(_locale),
      ),
    );
  }

  @override
  bool shouldReload(_FrenchCupertinoLocalizationsDelegate old) => false;
}

class _FrenchWidgetsLocalizationsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const _FrenchWidgetsLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == _locale;

  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      SynchronousFuture<WidgetsLocalizations>(const WidgetsLocalizationFr());

  @override
  bool shouldReload(_FrenchWidgetsLocalizationsDelegate old) => false;
}
