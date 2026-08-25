import 'package:as_grinta/features/matches/domain/match_meeting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('automatic meeting time is exactly 30 minutes before kickoff', () {
    final kickoff = DateTime(2026, 8, 26, 21);

    expect(
      resolvedMatchMeetingAt(kickoffAt: kickoff),
      DateTime(2026, 8, 26, 20, 30),
    );
  });

  test('custom meeting time overrides automatic meeting time', () {
    final kickoff = DateTime(2026, 8, 26, 21);
    final custom = DateTime(2026, 8, 26, 19, 45);

    expect(
      resolvedMatchMeetingAt(kickoffAt: kickoff, customMeetingAt: custom),
      custom,
    );
  });

  test('custom clock time follows a changed match date when still valid', () {
    final previousCustom = DateTime(2026, 8, 26, 19, 45);
    final newKickoff = DateTime(2026, 9, 2, 21);

    expect(
      preserveCustomMeetingTime(
        kickoffAt: newKickoff,
        customMeetingAt: previousCustom,
      ),
      DateTime(2026, 9, 2, 19, 45),
    );
  });

  test('invalid custom time falls back to automatic after kickoff change', () {
    final previousCustom = DateTime(2026, 8, 26, 20, 30);
    final earlierKickoff = DateTime(2026, 9, 2, 20);

    expect(
      preserveCustomMeetingTime(
        kickoffAt: earlierKickoff,
        customMeetingAt: previousCustom,
      ),
      isNull,
    );
  });

  test('custom meeting time must be before kickoff', () {
    final kickoff = DateTime(2026, 8, 26, 21);

    expect(
      validateCustomMeetingAt(
        kickoffAt: kickoff,
        customMeetingAt: DateTime(2026, 8, 26, 21),
      ),
      'L’heure de rendez-vous doit être avant le coup d’envoi.',
    );
    expect(
      validateCustomMeetingAt(
        kickoffAt: kickoff,
        customMeetingAt: DateTime(2026, 8, 26, 20, 59),
      ),
      isNull,
    );
  });
}
