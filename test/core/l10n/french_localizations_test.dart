import 'package:as_grinta/core/l10n/french_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les traductions réduites au français doivent rendre exactement ce que
/// rendaient les délégués complets de Flutter. Après une montée de version de
/// Flutter, un écart sur les formats de date fait échouer ce test.
void main() {
  const locale = Locale('fr', 'FR');

  Future<T> loadWith<T>(Iterable<LocalizationsDelegate<dynamic>> delegates) {
    final delegate = delegates.whereType<LocalizationsDelegate<T>>().single;
    expect(delegate.isSupported(locale), isTrue);
    return delegate.load(locale);
  }

  final dates = [
    DateTime(2026, 1, 4, 9, 5),
    DateTime(2026, 7, 14, 21, 30),
    DateTime(2027, 12, 31, 0, 0),
  ];

  test('calendrier et formats Material identiques', () async {
    final ours = await loadWith<MaterialLocalizations>(
      frenchLocalizationsDelegates,
    );
    final flutter = await loadWith<MaterialLocalizations>(
      GlobalMaterialLocalizations.delegates,
    );

    expect(ours.runtimeType, flutter.runtimeType);
    for (final date in dates) {
      expect(ours.formatYear(date), flutter.formatYear(date));
      expect(ours.formatCompactDate(date), flutter.formatCompactDate(date));
      expect(ours.formatShortDate(date), flutter.formatShortDate(date));
      expect(ours.formatMediumDate(date), flutter.formatMediumDate(date));
      expect(ours.formatFullDate(date), flutter.formatFullDate(date));
      expect(ours.formatMonthYear(date), flutter.formatMonthYear(date));
      expect(ours.formatShortMonthDay(date), flutter.formatShortMonthDay(date));
      expect(
        ours.formatTimeOfDay(TimeOfDay.fromDateTime(date)),
        flutter.formatTimeOfDay(TimeOfDay.fromDateTime(date)),
      );
      expect(ours.parseCompactDate(ours.formatCompactDate(date)), isNotNull);
    }
    expect(ours.narrowWeekdays, flutter.narrowWeekdays);
    expect(ours.firstDayOfWeekIndex, flutter.firstDayOfWeekIndex);
    expect(ours.dateHelpText, flutter.dateHelpText);
    expect(ours.okButtonLabel, flutter.okButtonLabel);
    expect(ours.formatDecimal(1234567), flutter.formatDecimal(1234567));
    expect(ours.formatHour(const TimeOfDay(hour: 7, minute: 0)),
        flutter.formatHour(const TimeOfDay(hour: 7, minute: 0)));
    expect(ours.formatMinute(const TimeOfDay(hour: 7, minute: 5)),
        flutter.formatMinute(const TimeOfDay(hour: 7, minute: 5)));
  });

  test('sélecteurs Cupertino identiques', () async {
    final ours = await loadWith<CupertinoLocalizations>(
      frenchLocalizationsDelegates,
    );
    final flutter = await loadWith<CupertinoLocalizations>(
      GlobalCupertinoLocalizations.delegates,
    );

    expect(ours.runtimeType, flutter.runtimeType);
    for (var day = 1; day <= 31; day += 7) {
      expect(ours.datePickerDayOfMonth(day, DateTime.monday),
          flutter.datePickerDayOfMonth(day, DateTime.monday));
    }
    for (var month = 1; month <= 12; month++) {
      expect(ours.datePickerMonth(month), flutter.datePickerMonth(month));
      expect(ours.datePickerStandaloneMonth(month),
          flutter.datePickerStandaloneMonth(month));
    }
    for (final date in dates) {
      expect(
          ours.datePickerMediumDate(date), flutter.datePickerMediumDate(date));
      expect(ours.datePickerYear(date.year), flutter.datePickerYear(date.year));
    }
    expect(ours.datePickerHour(7), flutter.datePickerHour(7));
    expect(ours.datePickerMinute(5), flutter.datePickerMinute(5));
    expect(ours.datePickerDateOrder, flutter.datePickerDateOrder);
    expect(ours.datePickerDateTimeOrder, flutter.datePickerDateTimeOrder);
  });

  test('textes généraux identiques', () async {
    final ours = await loadWith<WidgetsLocalizations>(
      frenchLocalizationsDelegates,
    );
    final flutter = await loadWith<WidgetsLocalizations>(
      GlobalMaterialLocalizations.delegates,
    );

    expect(ours.runtimeType, flutter.runtimeType);
    expect(ours.textDirection, flutter.textDirection);
    expect(ours.reorderItemUp, flutter.reorderItemUp);
  });

  testWidgets('le sélecteur de date s’affiche en français', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: const [locale],
        localizationsDelegates: frenchLocalizationsDelegates,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDatePicker(
              context: context,
              initialDate: DateTime(2026, 7, 14),
              firstDate: DateTime(2026),
              lastDate: DateTime(2027),
            ),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(find.text('juillet 2026'), findsOneWidget);
  });
}
