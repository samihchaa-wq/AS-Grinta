import 'package:as_grinta/features/sports_management/data/match_sport_report_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_sport_report.dart';
import 'package:flutter_test/flutter_test.dart';

MatchSportReport _report({
  required bool isValidated,
  required int version,
  int scoreAsGrinta = 2,
  int scoreAdverse = 1,
}) {
  return MatchSportReport.fromRpc({
    'match_id': 'match-1',
    'opponent_name': 'Nantes',
    'is_home': true,
    'kickoff_at':
        DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
    'match_status': 'termine',
    'is_validated': isValidated,
    'version': version,
    'score_as_grinta': scoreAsGrinta,
    'score_adverse': scoreAdverse,
    'is_correction': version > 0,
    'is_editable': true,
    'participants': const <Map<String, dynamic>>[],
    'lineup': {
      'match_id': 'match-1',
      'formation_code': '4-4-2',
      'entries': const <Map<String, dynamic>>[],
    },
    'goal_actions': const <Map<String, dynamic>>[],
  });
}

void main() {
  group('matchSportReportWriteLanded', () {
    test('recognises our own validation by its higher version', () {
      expect(
        matchSportReportWriteLanded(
          current: _report(isValidated: true, version: 1),
          knownVersion: 0,
          scoreAsGrinta: 2,
          scoreAdverse: 1,
        ),
        isTrue,
      );
    });

    test('rejects an unchanged version', () {
      // Le serveur n'a rien enregistré : relire le même état ne prouve rien.
      expect(
        matchSportReportWriteLanded(
          current: _report(isValidated: true, version: 1),
          knownVersion: 1,
          scoreAsGrinta: 2,
          scoreAdverse: 1,
        ),
        isFalse,
      );
    });

    test('rejects a report that is not validated', () {
      expect(
        matchSportReportWriteLanded(
          current: _report(isValidated: false, version: 1),
          knownVersion: 0,
          scoreAsGrinta: 2,
          scoreAdverse: 1,
        ),
        isFalse,
      );
    });

    test('rejects a concurrent validation carrying another score', () {
      // Quelqu'un d'autre a valide entre-temps : la version a bien augmente,
      // mais ce n'est pas notre ecriture.
      expect(
        matchSportReportWriteLanded(
          current: _report(
            isValidated: true,
            version: 1,
            scoreAsGrinta: 5,
            scoreAdverse: 0,
          ),
          knownVersion: 0,
          scoreAsGrinta: 2,
          scoreAdverse: 1,
        ),
        isFalse,
      );
    });

    test('recognises a correction over an already validated report', () {
      expect(
        matchSportReportWriteLanded(
          current: _report(isValidated: true, version: 3),
          knownVersion: 2,
          scoreAsGrinta: 2,
          scoreAdverse: 1,
        ),
        isTrue,
      );
    });
  });
}
