import 'package:as_grinta/features/matches/domain/calendar_export.dart';
import 'package:as_grinta/features/matches/domain/club_event.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ICS export contains season matches, events and skips cancelled ones',
      () {
    final matches = [
      MatchModel(
        id: 'm1',
        seasonId: 's1',
        opponentId: 'o1',
        kickoffAt: DateTime.utc(2026, 9, 5, 19, 30),
        isHome: true,
        plannedDurationMinutes: 90,
        status: 'a_venir',
        grintaScore: null,
        opponentScore: null,
        opponentName: 'FC Test',
        seasonName: '2026-2027',
        address: 'Stade Test, Toulouse',
      ),
      MatchModel(
        id: 'm2',
        seasonId: 's1',
        opponentId: 'o2',
        kickoffAt: DateTime.utc(2026, 9, 12, 19, 30),
        isHome: false,
        plannedDurationMinutes: 90,
        status: 'annule',
        grintaScore: null,
        opponentScore: null,
        opponentName: 'FC Annulé',
        seasonName: '2026-2027',
      ),
    ];
    final events = [
      ClubEvent(
        id: 'e1',
        seasonId: 's1',
        title: 'Soirée du club',
        startsAt: DateTime.utc(2026, 9, 20, 18, 0),
        location: 'Club house, Toulouse',
        createdBy: 'admin-1',
      ),
    ];

    final ics = buildSeasonIcs(
      seasonName: '2026-2027',
      matches: matches,
      events: events,
      generatedAt: DateTime.utc(2026, 8, 5, 8),
    );

    expect(ics, contains('BEGIN:VCALENDAR'));
    expect(ics, contains('X-WR-CALNAME:AS La Grinta 2026-2027'));
    expect(ics, contains('SUMMARY:AS Grinta - FC Test'));
    expect(ics, contains('LOCATION:Stade Test\\, Toulouse'));
    expect(ics, contains('DTSTART:20260905T193000Z'));
    expect(ics, contains('SUMMARY:Soirée du club'));
    expect(ics, contains('LOCATION:Club house\\, Toulouse'));
    expect(ics, contains('DTSTART:20260920T180000Z'));
    expect(ics, isNot(contains('FC Annulé')));
    expect(ics, contains('END:VCALENDAR'));
  });
}
