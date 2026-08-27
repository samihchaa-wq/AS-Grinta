import 'package:as_grinta/features/match_live/data/match_live_repository.dart';
import 'package:as_grinta/features/match_live/domain/match_live_timeline.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/match_faits_du_match_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpCard(WidgetTester tester, MatchLiveTimeline? timeline) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchLiveRepositoryProvider
              .overrideWithValue(_TimelineOnlyRepository(timeline)),
        ],
        child: const MaterialApp(
          home: Scaffold(body: MatchFaitsDuMatchCard(matchId: 'match-1')),
        ),
      ),
    );
  }

  testWidgets('les faits du match s’affichent tant qu’il en reste', (
    tester,
  ) async {
    await pumpCard(
      tester,
      MatchLiveTimeline.tryFromRpc({
        'match_id': 'match-1',
        'events': [
          {
            'event_type': 'goal_us',
            'minute': 12,
            'half': 1,
            'scorer_name': 'Flo',
            'assist_name': 'Sam',
            'score_as_grinta_after': 1,
          },
        ],
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('Faits du match'), findsOneWidget);
    expect(find.text('Flo (passe Sam)'), findsOneWidget);
  });

  testWidgets('une chronologie vidée fait disparaître tout le bloc', (
    tester,
  ) async {
    await pumpCard(
      tester,
      MatchLiveTimeline.tryFromRpc({
        'match_id': 'match-1',
        'events': <Object>[],
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('Faits du match'), findsNothing);
  });
}

/// Ne sert qu'à la chronologie : tout le reste du contrat Live n'est pas
/// sollicité par la carte « Faits du match ».
class _TimelineOnlyRepository implements MatchLiveRepository {
  _TimelineOnlyRepository(this.timeline);

  final MatchLiveTimeline? timeline;

  @override
  Future<MatchLiveTimeline?> fetchTimeline(String matchId) async => timeline;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
