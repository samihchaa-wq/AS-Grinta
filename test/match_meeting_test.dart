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

  test('automatic meeting time can fall on the previous day', () {
    final kickoff = DateTime(2026, 8, 27, 0, 15);

    expect(
      resolvedMatchMeetingAt(kickoffAt: kickoff),
      DateTime(2026, 8, 26, 23, 45),
    );
  });

  test('custom meeting time overrides automatic meeting time', () {
    final kickoff = DateTime(2026, 8, 26, 21);
    final custom = DateTime(2026, 8, 25, 19, 45);

    expect(
      resolvedMatchMeetingAt(kickoffAt: kickoff, customMeetingAt: custom),
      custom,
    );
  });

  test('custom meeting keeps its day offset when the match date moves', () {
    final previousKickoff = DateTime(2026, 8, 26, 21);
    final previousCustom = DateTime(2026, 8, 25, 19, 45);
    final newKickoff = DateTime(2026, 9, 2, 21);

    expect(
      preserveCustomMeetingTime(
        kickoffAt: newKickoff,
        customMeetingAt: previousCustom,
        previousKickoffAt: previousKickoff,
      ),
      DateTime(2026, 9, 1, 19, 45),
    );
  });

  test('custom time on match day follows a changed match date', () {
    final previousKickoff = DateTime(2026, 8, 26, 21);
    final previousCustom = DateTime(2026, 8, 26, 19, 45);
    final newKickoff = DateTime(2026, 9, 2, 21);

    expect(
      preserveCustomMeetingTime(
        kickoffAt: newKickoff,
        customMeetingAt: previousCustom,
        previousKickoffAt: previousKickoff,
      ),
      DateTime(2026, 9, 2, 19, 45),
    );
  });

  test('invalid custom time falls back to automatic after kickoff change', () {
    final previousKickoff = DateTime(2026, 8, 26, 21);
    final previousCustom = DateTime(2026, 8, 26, 20, 30);
    final earlierKickoff = DateTime(2026, 9, 2, 20);

    expect(
      preserveCustomMeetingTime(
        kickoffAt: earlierKickoff,
        customMeetingAt: previousCustom,
        previousKickoffAt: previousKickoff,
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
        customMeetingAt: DateTime(2026, 8, 25, 20, 59),
      ),
      isNull,
    );
  });
}
