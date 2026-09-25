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

  testWidgets(
      'l’en-tête de la fiche reprend la carte du calendrier, sans lignes '
      'HDM, buteurs ni passeurs', (tester) async {
    const address =
        'Complexe sportif - Chemin des Garrosses - 31180 - Rouffiac-Tolosan';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MatchDetailHeaderCard(
              homeName: 'Rouffiac Tolosan FC',
              awayName: 'AS Grinta',
              grintaIsHome: false,
              homeScore: 2,
              awayScore: 8,
              finished: true,
              kickoffAt: DateTime(2026, 5, 21, 21),
              matchType: 'championnat',
              typeLabel: calendarMatchTypeLabel('championnat', 23),
              address: address,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('21 Mai 2026'), findsOneWidget);
    expect(find.textContaining('Championnat · J23'), findsOneWidget);
    expect(find.text('2 – 8'), findsOneWidget);
    expect(find.text(address), findsOneWidget);
    expect(find.textContaining('HDM'), findsNothing);
    expect(find.textContaining('Buteurs'), findsNothing);
    expect(find.textContaining('Passeurs'), findsNothing);
  });

  testWidgets('avant le match, l’en-tête affiche VS à la place du score', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MatchDetailHeaderCard(
              homeName: 'Toulouse Métropole',
              awayName: 'AS Grinta',
              grintaIsHome: false,
              kickoffAt: DateTime(2026, 9, 28, 21),
              matchType: 'amical',
              typeLabel: calendarMatchTypeLabel('amical', null),
            ),
          ),
        ),
      ),
    );

    expect(find.text('VS'), findsOneWidget);
    expect(find.textContaining('Amical'), findsOneWidget);
  });

  testWidgets('le lien vers le vote HDM en cours reste dans l’en-tête', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MatchDetailHeaderCard(
              homeName: 'AS Grinta',
              awayName: 'Test FC',
              grintaIsHome: true,
              homeScore: 1,
              awayScore: 0,
              finished: true,
              kickoffAt: DateTime(2026, 8, 27, 21),
              motmActionLabel: 'Voter pour l’Homme du match',
              onMotmTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Voter pour l’Homme du match'));
    expect(tapped, isTrue);
  });
}
