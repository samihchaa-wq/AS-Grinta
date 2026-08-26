import 'package:as_grinta/features/matches/presentation/widgets/match_meeting_time_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('meeting picker shows -30min by default', (tester) async {
    await tester.pumpWidget(
      _harness(kickoffAt: DateTime(2026, 8, 26, 21), customMeetingAt: null),
    );

    expect(find.text('Heure de rendez-vous'), findsOneWidget);
    expect(find.text('-30min'), findsOneWidget);
    expect(find.text('Choisir'), findsOneWidget);
    expect(find.text('Rendez-vous à 20:30'), findsOneWidget);
  });

  testWidgets('custom rendez-vous opens the scrolling date/time picker', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(kickoffAt: DateTime(2026, 8, 26, 21), customMeetingAt: null),
    );

    await tester.tap(find.text('Choisir'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    expect(find.text('Valider'), findsOneWidget);
  });

  testWidgets('meeting picker shows an explicit custom date and time', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        kickoffAt: DateTime(2026, 8, 26, 21),
        customMeetingAt: DateTime(2026, 8, 25, 19, 45),
      ),
    );

    expect(find.text('25/08/2026 · 19:45'), findsOneWidget);
  });
}

Widget _harness({
  required DateTime kickoffAt,
  required DateTime? customMeetingAt,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MatchMeetingTimePicker(
        kickoffAt: kickoffAt,
        customMeetingAt: customMeetingAt,
        enabled: true,
        onChanged: (_) {},
      ),
    ),
  );
}
