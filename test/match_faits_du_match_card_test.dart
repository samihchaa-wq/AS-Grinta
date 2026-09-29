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
          matchLiveRepositoryProvider
              .overrideWithValue(_TimelineOnlyRepository(timeline)),
          matchSportReportRepositoryProvider
              .overrideWithValue(_GoalActionsOnlyRepository(goals)),
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

  MatchGoalAction goal(
    Map<String, Object?> json, [
    int index = 0,
  ]) =>
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
    expect(find.text('Sofiane (passe Yanis)'), findsNothing);

    await openCard(tester);
    expect(find.text('Sofiane (passe Yanis)'), findsOneWidget);
    expect(find.text('Karim'), findsNothing);
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
    expect(find.text('Samih'), findsOneWidget);
    expect(find.text('But adverse'), findsOneWidget);
    expect(find.text('1-0'), findsOneWidget);
    expect(find.text('1-1'), findsOneWidget);

    // Le but adverse est visuellement poussé plus à droite que le but Grinta.
    expect(
      tester.getCenter(find.text('But adverse')).dx,
      greaterThan(tester.getCenter(find.text('Samih')).dx),
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

  testWidgets('les remplacements du direct rejoignent la chronologie', (
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

    expect(find.text('Samih'), findsOneWidget);
    expect(find.text('Nabil'), findsOneWidget);
    expect(find.text('Karim'), findsOneWidget);

    final tile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('Nabil'),
        matching: find.byType(ListTile),
      ),
    );
    expect(tile.contentPadding, const EdgeInsets.fromLTRB(0, 0, 6, 0));
    expect(tile.horizontalTitleGap, 0);
    expect(tile.minLeadingWidth, 0);
  });

  testWidgets('chaque salve n’affiche son repère qu’une fois, centré sur le groupe',
      (tester) async {
    Map<String, Object?> sub(String id, int minute, int half) => {
          'id': id,
          'event_type': 'substitution',
          'minute': minute,
          'half': half,
          'player_in_name': 'In$id',
          'player_out_name': 'Out$id',
        };
    await pumpCard(
      tester,
      timeline: MatchLiveTimeline.tryFromRpc({
        'match_id': 'match-1',
        'events': [
          sub('a', 5, 1),
          sub('b', 5, 1),
          sub('c', 32, 1),
          sub('d', 50, 2),
          sub('e', 50, 2),
        ],
      }),
    );
    await tester.pumpAndSettle();
    await openCard(tester);

    expect(find.text('1.1'), findsOneWidget);
    expect(find.text('1.2'), findsOneWidget);
    // La numérotation des salves repart à la reprise.
    expect(find.text('2.1'), findsOneWidget);
    expect(find.byIcon(Icons.swap_horiz_rounded), findsNothing);

    final firstSalvoCenter = tester.getCenter(find.text('1.1')).dy;
    final firstRowCenter = tester.getCenter(find.text('Ina')).dy;
    final secondRowCenter = tester.getCenter(find.text('Inb')).dy;
    expect(
      firstSalvoCenter,
      closeTo((firstRowCenter + secondRowCenter) / 2, 1),
    );

    final badge = tester.widget<Text>(find.text('1.1'));
    expect(badge.style?.color, Colors.white);
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
  }) =>
      Future<MatchSportReport>.error(UnimplementedError('submit'));

  @override
  Future<MatchSportReport> attachPlayer({
    required String matchId,
    String? seasonPlayerId,
    String? guestPlayerId,
    String? firstName,
    String? lastName,
    bool isGoalkeeper = false,
    String? reason,
  }) =>
      Future<MatchSportReport>.error(UnimplementedError('attachPlayer'));
}
