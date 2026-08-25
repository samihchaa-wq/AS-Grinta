import 'package:as_grinta/features/matches/presentation/widgets/match_meeting_time_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('meeting picker shows automatic H-30 by default', (tester) async {
    await tester.pumpWidget(
      _harness(kickoffAt: DateTime(2026, 8, 26, 21), customMeetingAt: null),
    );

    expect(find.text('Heure de rendez-vous'), findsOneWidget);
    expect(find.text('30 min avant le coup d’envoi · 20:30'), findsOneWidget);

    await tester.tap(find.text('Heure de rendez-vous'));
    await tester.pumpAndSettle();

    expect(find.text('30 min avant le coup d’envoi'), findsOneWidget);
    expect(find.text('Choisir une heure'), findsOneWidget);
  });

  testWidgets('meeting picker shows an explicit custom time', (tester) async {
    await tester.pumpWidget(
      _harness(
        kickoffAt: DateTime(2026, 8, 26, 21),
        customMeetingAt: DateTime(2026, 8, 26, 19, 45),
      ),
    );

    expect(find.text('Personnalisée · 19:45'), findsOneWidget);
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
