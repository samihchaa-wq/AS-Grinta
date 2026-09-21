import 'package:as_grinta/features/matches/presentation/match_encounter_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('matchEncounterRoute', () {
    test('opens a current calendar match', () {
      expect(
        matchEncounterRoute(
          encounterId: '11111111-1111-1111-1111-111111111111',
          isHistorical: false,
        ),
        '/matches/11111111-1111-1111-1111-111111111111',
      );
    });

    test('opens an archived calendar match', () {
      expect(
        matchEncounterRoute(
          encounterId: '22222222-2222-2222-2222-222222222222',
          isHistorical: true,
        ),
        '/matches/history/22222222-2222-2222-2222-222222222222',
      );
    });

    test('disables navigation while the backend id is unavailable', () {
      expect(
        matchEncounterRoute(encounterId: '  ', isHistorical: true),
        isNull,
      );
      expect(
        matchEncounterRoute(encounterId: null, isHistorical: false),
        isNull,
      );
    });
  });
}
