import 'package:as_grinta/features/match_live/data/match_live_repository.dart';
import 'package:as_grinta/features/match_live/domain/match_live_timeline.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/match_faits_du_match_card.dart';
import 'package:as_grinta/features/sports_management/data/match_sport_report_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/match_goal_action.dart';
import 'package:as_grinta/features/sports_management/domain/match_sport_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Le bloc « Faits du match » de la fiche affiche le compte rendu validé, pas
/// le brouillon saisi en direct : une correction se voit tout de suite.
void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    List<MatchGoalAction> goals = const [],
    MatchLiveTimeline? timeline,
  }) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchLiveRepositoryProvider.overrideWithValue(
            _TimelineOnlyRepository(timeline),
          ),
          matchSportReportRepositoryProvider.overrideWithValue(
            _GoalActionsOnlyRepository(goals),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: MatchFaitsDuMatchCard(matchId: 'match-1')),
        ),
      ),
    );
  }

  Future<void> openCard(WidgetTester tester) async {
    await tester.tap(find.text('Faits du match'));
    await tester.pumpAndSettle();
  }

  MatchGoalAction goal(Map<String, Object?> json, [int index = 0]) =>
      MatchGoalAction.fromJson(json, index);

  testWidgets('les buts affichés sont ceux du compte rendu validé', (
    tester,
  ) async {
    await pumpCard(
      tester,
      goals: [
        goal({
          'id': 'g1',
          'minute': 34,
          'team_side': 'as_grinta',
          'scorer_participant_id': 'p1',
          'scorer_name': 'Sofiane',
          'assist_participant_id': 'p2',
          'assist_name': 'Yanis',
          'assist_kind': 'player',
        }),
      ],
      // Le brouillon du direct attribuait ce but à quelqu'un d'autre : c'est
      // la correction qui doit s'afficher.
      timeline: MatchLiveTimeline.tryFromRpc({
        'match_id': 'match-1',
        'events': [
          {
            'event_type': 'goal_us',
            'minute': 34,
            'half': 1,
            'scorer_name': 'Karim',
            'score_as_grinta_after': 1,
          },
        ],
      }),
    );
    await tester.pumpAndSettle();

    // Le bloc est fermé à l'ouverture de la fiche.
    expect(find.text('Faits du match'), findsOneWidget);
    expect(find.text('Sofiane (Yanis)', findRichText: true), findsNothing);

    await openCard(tester);
    expect(find.text('Sofiane (Yanis)', findRichText: true), findsOneWidget);
    expect(find.text('Karim', findRichText: true), findsNothing);
  });

  testWidgets('un match saisi sans direct a aussi sa chronologie', (
    tester,
  ) async {
    await pumpCard(
      tester,
      goals: [
        goal({
          'id': 'g1',
          'minute': 12,
          'team_side': 'as_grinta',
          'scorer_name': 'Samih',
          'scorer_participant_id': 'p1',
          'assist_kind': 'none',
        }),
        goal({
          'id': 'g2',
          'minute': 25,
          'team_side': 'opponent',
          'assist_kind': 'none',
        }, 1),
      ],
      // Aucun suivi en direct : la chronologie vient uniquement du compte rendu.
      timeline: null,
    );
    await tester.pumpAndSettle();
    await openCard(tester);

    expect(find.text('Faits du match'), findsOneWidget);
    expect(find.text('Samih', findRichText: true), findsOneWidget);
    expect(find.text('But adverse', findRichText: true), findsOneWidget);
    expect(find.text('1 - 0'), findsOneWidget);
    expect(find.text('1 - 1'), findsOneWidget);

    // Comme sur les sites de résultats : le but de l'équipe qui reçoit part
    // de la gauche avec sa minute au bord gauche, le but adverse de la droite.
    expect(
      tester.getCenter(find.text('1 - 1')).dx,
      greaterThan(tester.getCenter(find.text('1 - 0')).dx),
    );
    expect(
      tester.getCenter(find.text("12'")).dx,
      lessThan(tester.getCenter(find.text('Samih', findRichText: true)).dx),
    );
    expect(
      tester.getCenter(find.text("25'")).dx,
      greaterThan(
        tester.getCenter(find.text('But adverse', findRichText: true)).dx,
      ),
    );
  });

  testWidgets('une minute inconnue s’affiche sans inventer d’horaire', (
    tester,
  ) async {
    await pumpCard(
      tester,
      goals: [
        goal({
          'id': 'g1',
          'minute': null,
          'team_side': 'as_grinta',
          'scorer_name': 'Samih',
          'scorer_participant_id': 'p1',
          'assist_kind': 'unknown',
        }),
      ],
    );
    await tester.pumpAndSettle();
    await openCard(tester);

    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('les remplacements du direct ne figurent pas dans la fiche', (
    tester,
  ) async {
    await pumpCard(
      tester,
      goals: [
        goal({
          'id': 'g1',
          'minute': 12,
          'team_side': 'as_grinta',
          'scorer_name': 'Samih',
          'scorer_participant_id': 'p1',
          'assist_kind': 'none',
        }),
      ],
      timeline: MatchLiveTimeline.tryFromRpc({
        'match_id': 'match-1',
        'events': [
          {
            'id': 'a',
            'event_type': 'substitution',
            'minute': 60,
            'half': 2,
            'player_in_name': 'Nabil',
            'player_out_name': 'Karim',
          },
        ],
      }),
    );
    await tester.pumpAndSettle();
    await openCard(tester);

    expect(find.text('Samih', findRichText: true), findsOneWidget);
    expect(find.text('Nabil', findRichText: true), findsNothing);
    expect(find.text('Karim', findRichText: true), findsNothing);
    expect(find.text('2.1'), findsNothing);
  });

  testWidgets('des remplacements sans but ne font pas apparaître le bloc', (
    tester,
  ) async {
    await pumpCard(
      tester,
      timeline: MatchLiveTimeline.tryFromRpc({
        'match_id': 'match-1',
        'events': [
          {
            'id': 'a',
            'event_type': 'substitution',
            'minute': 5,
            'half': 1,
            'player_in_name': 'Banc1',
            'player_out_name': 'Titu1',
          },
        ],
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('Faits du match'), findsNothing);
  });

  testWidgets('sans aucun fait, le bloc disparaît', (tester) async {
    await pumpCard(tester);
    await tester.pumpAndSettle();

    expect(find.text('Faits du match'), findsNothing);
  });
}

/// Ne sert qu'à la chronologie du direct : le reste du contrat Live n'est pas
/// sollicité par la carte « Faits du match ».
class _TimelineOnlyRepository implements MatchLiveRepository {
  _TimelineOnlyRepository(this.timeline);

  final MatchLiveTimeline? timeline;

  @override
  Future<MatchLiveTimeline?> fetchTimeline(String matchId) async => timeline;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Ne sert qu'aux buts définitifs du compte rendu.
class _GoalActionsOnlyRepository implements MatchSportReportRepository {
  _GoalActionsOnlyRepository(this.goals);

  final List<MatchGoalAction> goals;

  @override
  Future<List<MatchGoalAction>> fetchGoalActions(String matchId) async => goals;

  @override
  Future<MatchSportReport> fetch(String matchId) =>
      Future<MatchSportReport>.error(UnimplementedError('fetch'));

  @override
  Future<MatchSportReport> submit({
    required String matchId,
    required int knownVersion,
    required int scoreAsGrinta,
    required int scoreAdverse,
    required MatchComposition lineup,
    required List<MatchGoalAction> goalActions,
    String? reason,
  }) => Future<MatchSportReport>.error(UnimplementedError('submit'));

  @override
  Future<MatchSportReport> attachPlayer({
    required String matchId,
    String? seasonPlayerId,
    String? guestPlayerId,
    String? firstName,
    String? lastName,
    bool isGoalkeeper = false,
    String? reason,
  }) => Future<MatchSportReport>.error(UnimplementedError('attachPlayer'));
}
