import 'package:as_grinta/core/widgets/match_detail_header_card.dart';
import 'package:as_grinta/features/match_live/domain/match_live_event.dart';
import 'package:as_grinta/features/match_live/domain/match_live_state_bundle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('un but Live transporte son passeur décisif', () {
    final event = MatchLiveEvent.fromJson({
      'id': 'event-1',
      'event_type': 'goal_us',
      'minute': 12,
      'half': 1,
      'scorer_participant_id': 'participant-1',
      'scorer_name': 'Flo',
      'assist_participant_id': 'participant-2',
      'assist_name': 'Sam',
      'score_as_grinta_after': 1,
    });

    expect(event.scorerName, 'Flo');
    expect(event.assistParticipantId, 'participant-2');
    expect(event.assistName, 'Sam');
    expect(event.needsScorer, isFalse);
  });

  test('un but sans passeur ne renvoie aucune passe décisive', () {
    final event = MatchLiveEvent.fromJson({
      'id': 'event-2',
      'event_type': 'goal_us',
      'minute': 30,
      'half': 1,
      'scorer_participant_id': 'participant-1',
      'scorer_name': 'Flo',
      'assist_participant_id': null,
      'assist_name': null,
      'score_as_grinta_after': 2,
    });

    expect(event.assistParticipantId, isNull);
    expect(event.assistName, isNull);
  });

  test('le récapitulatif Live compte une passe décisive par but', () {
    final bundle = MatchLiveStateBundle.fromRpc({
      'match_id': 'match-1',
      'state': 'finished',
      'half': 2,
      'elapsed_seconds': 0,
      'score_as_grinta': 2,
      'score_adverse': 0,
      'events': [
        {
          'id': 'goal-1',
          'event_type': 'goal_us',
          'minute': 10,
          'half': 1,
          'scorer_participant_id': 'flo',
          'assist_participant_id': 'sam',
          'score_as_grinta_after': 1,
        },
        {
          'id': 'goal-2',
          'event_type': 'goal_us',
          'minute': 60,
          'half': 2,
          'scorer_participant_id': 'sam',
          'assist_participant_id': 'flo',
          'score_as_grinta_after': 2,
        },
        {
          'id': 'goal-3',
          'event_type': 'goal_them',
          'minute': 70,
          'half': 2,
          'score_adverse_after': 1,
        },
      ],
    });

    final assists = <String, int>{};
    for (final event in bundle.ownGoals) {
      final id = event.assistParticipantId;
      if (id == null) continue;
      assists[id] = (assists[id] ?? 0) + 1;
    }

    expect(bundle.ownGoals.length, 2);
    expect(assists, {'sam': 1, 'flo': 1});
  });

  testWidgets('la fiche du match annonce les passeurs décisifs', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MatchDetailHeaderCard(
              homeName: 'AS Grinta',
              awayName: 'Test FC',
              grintaIsHome: true,
              homeScore: 3,
              awayScore: 0,
              dateLabel: '27 août 2026',
              scorerLabels: ['Flo ×2', 'Sam'],
              assistLabels: ['Sam ×2', 'Flo'],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Buteurs · Flo ×2 · Sam'), findsOneWidget);
    expect(find.text('Passeurs · Sam ×2 · Flo'), findsOneWidget);
  });

  testWidgets(
    'un match sans passe décisive suivie n’affiche pas la ligne Passeurs',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MatchDetailHeaderCard(
                homeName: 'AS Grinta',
                awayName: 'Test FC',
                grintaIsHome: true,
                homeScore: 1,
                awayScore: 0,
                dateLabel: '27 août 2026',
                scorerLabels: ['Flo'],
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('Passeurs'), findsNothing);
    },
  );
}
