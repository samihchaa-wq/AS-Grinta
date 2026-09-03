import 'package:as_grinta/features/sports_management/data/match_sport_report_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/match_goal_action.dart';
import 'package:as_grinta/features/sports_management/domain/match_sport_report.dart';
import 'package:as_grinta/features/sports_management/presentation/match_report_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// L'écran « Compte rendu » : deux onglets, une seule validation, et un score
/// qui ne peut jamais s'écarter des buts saisis.
void main() {
  testWidgets('les deux onglets texte et la validation unique sont présents', (
    tester,
  ) async {
    await _pump(tester, _repository(_report()));

    final effectifTab = find.widgetWithText(Tab, 'Effectif');
    final factsTab = find.widgetWithText(Tab, 'Faits du match');
    expect(effectifTab, findsOneWidget);
    expect(factsTab, findsOneWidget);
    expect(
      find.descendant(of: effectifTab, matching: find.byType(Icon)),
      findsNothing,
    );
    expect(
      find.descendant(of: factsTab, matching: find.byType(Icon)),
      findsNothing,
    );
    expect(find.text('VALIDER LE COMPTE RENDU'), findsOneWidget);
    // Une seule action globale : pas de validation par module.
    expect(find.textContaining('Valider l’effectif'), findsNothing);
    expect(find.text('Statistiques'), findsNothing);
  });

  testWidgets('sans composition, tout l’effectif est sur le banc', (
    tester,
  ) async {
    await _pump(tester, _repository(_report()));

    expect(find.textContaining('Banc (3)'), findsOneWidget);
    expect(
      find.textContaining('Personne n’est encore sur le terrain'),
      findsOneWidget,
    );
  });

  testWidgets('un match sans Live crée les buts manquants depuis le score', (
    tester,
  ) async {
    await _pump(
      tester,
      _repository(_report(scoreAsGrinta: 3, scoreAdverse: 1)),
    );

    await tester.tap(find.widgetWithText(Tab, 'Faits du match'));
    await tester.pumpAndSettle();

    // 3 buts AS Grinta à compléter, chacun sans buteur attribué…
    expect(find.text('Non attribué'), findsNWidgets(3));
    // …et 1 but adverse.
    expect(find.text('But de Nantes'), findsOneWidget);
  });

  testWidgets('les buts du Live gardent leur buteur et leur passeur', (
    tester,
  ) async {
    await _pump(
      tester,
      _repository(
        _report(
          scoreAsGrinta: 1,
          scoreAdverse: 0,
          goalActions: [
            MatchGoalAction.fromJson({
              'id': 'goal-1',
              'minute': 12,
              'team_side': 'as_grinta',
              'scorer_participant_id': 'p1',
              'scorer_name': 'Samih',
              'assist_participant_id': 'p2',
              'assist_name': 'Nabil',
              'assist_kind': 'player',
              'source': 'live',
            }, 0),
          ],
        ),
      ),
    );

    await tester.tap(find.widgetWithText(Tab, 'Faits du match'));
    await tester.pumpAndSettle();

    expect(find.text('Samih'), findsOneWidget);
    expect(find.text('Nabil'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('baisser le score demande quel but supprimer', (tester) async {
    await _pump(tester, _repository(_report(scoreAsGrinta: 2)));

    // Le « moins » de la ligne AS Grinta.
    await tester.tap(find.byIcon(Icons.remove).first);
    await tester.pumpAndSettle();

    expect(find.text('Quel but souhaitez-vous supprimer ?'), findsOneWidget);
    // Les deux buts existants sont proposés : rien n'est supprimé d'office.
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
  });

  testWidgets('un match déjà validé n’affiche plus de bandeau de correction', (
    tester,
  ) async {
    await _pump(tester, _repository(_report(isCorrection: true)));

    expect(
      find.textContaining('Correction d’un match déjà validé'),
      findsNothing,
    );
  });

  testWidgets('hors fenêtre de correction, le compte rendu est verrouillé', (
    tester,
  ) async {
    await _pump(
      tester,
      _repository(_report(isCorrection: true, isEditable: false)),
    );

    expect(
      find.textContaining('La fenêtre de correction est fermée'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'VALIDER LE COMPTE RENDU'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('la validation envoie effectif et faits du match ensemble', (
    tester,
  ) async {
    final repository = _repository(_report(scoreAsGrinta: 1));
    await _pump(tester, repository);

    await tester.tap(find.text('VALIDER LE COMPTE RENDU'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Valider'));
    await tester.pumpAndSettle();

    expect(repository.submitted, isNotNull);
    expect(repository.submitted!.scoreAsGrinta, 1);
    expect(repository.submitted!.goalActions.length, 1);
    expect(repository.submitted!.lineup.entries.length, 3);
  });

  testWidgets('la validation transmet la version affichee au depot', (
    tester,
  ) async {
    // Sans cette version, une relecture apres coupure reseau ne pourrait pas
    // distinguer notre ecriture d'un etat anterieur portant le meme score.
    final repository = _repository(_report(isCorrection: true));
    await _pump(tester, repository);

    await tester.tap(find.text('VALIDER LE COMPTE RENDU'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Corriger'));
    await tester.pumpAndSettle();

    expect(repository.submittedKnownVersion, 1);
  });
}

Future<void> _pump(
    WidgetTester tester, _FakeReportRepository repository) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        matchSportReportRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        // Les vagues d'encre chargent un shader indisponible dans certains
        // environnements de test : le rendu n'apporte rien ici.
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: const Scaffold(body: MatchReportView(matchId: 'match-1')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MatchSportReport _report({
  int scoreAsGrinta = 0,
  int scoreAdverse = 0,
  bool isCorrection = false,
  bool isEditable = true,
  List<MatchGoalAction> goalActions = const [],
}) {
  return MatchSportReport.fromRpc({
    'match_id': 'match-1',
    'opponent_name': 'Nantes',
    'is_home': true,
    'kickoff_at':
        DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
    'match_status': 'termine',
    'is_validated': isCorrection,
    'version': isCorrection ? 1 : 0,
    'score_as_grinta': scoreAsGrinta,
    'score_adverse': scoreAdverse,
    'is_correction': isCorrection,
    'is_editable': isEditable,
    'correction_closes_at':
        DateTime.now().add(const Duration(hours: 12)).toIso8601String(),
    'participants': [
      for (final id in ['p1', 'p2', 'p3'])
        {
          'participant_id': id,
          'display_name': 'Joueur $id',
          'is_guest': false,
          'is_goalkeeper': id == 'p1',
          'present': true,
          'final_selection_status': 'substitute',
          'goals': 0,
          'assists': 0,
          'clean_sheet': false,
        },
    ],
    'lineup': {
      'match_id': 'match-1',
      'formation_code': '4-4-2',
      'entries': [
        for (final id in ['p1', 'p2', 'p3'])
          {
            'participant_id': id,
            'season_player_id': 'season-$id',
            'display_name': id == 'p1'
                ? 'Samih'
                : id == 'p2'
                    ? 'Nabil'
                    : 'Karim',
            'is_goalkeeper': id == 'p1',
            'zone': 'bench',
            'sort_order': 0,
            'availability_status': 'available',
            'convocation_status': 'convoked',
            'selection_status': 'substitute',
          },
      ],
    },
    'goal_actions': [for (final goal in goalActions) _goalJson(goal)],
    'add_player_options': {'roster': <Object>[], 'guests': <Object>[]},
  });
}

Map<String, Object?> _goalJson(MatchGoalAction goal) => {
      'id': goal.id,
      'minute': goal.minute,
      'team_side': goal.teamSide.wireValue,
      'scorer_participant_id': goal.scorerParticipantId,
      'scorer_name': goal.scorerName,
      'assist_participant_id': goal.assistParticipantId,
      'assist_name': goal.assistName,
      'assist_kind': goal.assistKind.wireValue,
      'is_own_goal': goal.isOwnGoal,
      'source': goal.source,
    };

_FakeReportRepository _repository(MatchSportReport report) =>
    _FakeReportRepository(report);

typedef _Submission = ({
  int scoreAsGrinta,
  int scoreAdverse,
  MatchComposition lineup,
  List<MatchGoalAction> goalActions,
});

class _FakeReportRepository implements MatchSportReportRepository {
  _FakeReportRepository(this.report);

  final MatchSportReport report;
  _Submission? submitted;
  int? submittedKnownVersion;

  @override
  Future<MatchSportReport> fetch(String matchId) async => report;

  @override
  Future<List<MatchGoalAction>> fetchGoalActions(String matchId) async =>
      report.goalActions;

  @override
  Future<MatchSportReport> submit({
    required String matchId,
    required int knownVersion,
    required int scoreAsGrinta,
    required int scoreAdverse,
    required MatchComposition lineup,
    required List<MatchGoalAction> goalActions,
    String? reason,
  }) async {
    submittedKnownVersion = knownVersion;
    submitted = (
      scoreAsGrinta: scoreAsGrinta,
      scoreAdverse: scoreAdverse,
      lineup: lineup,
      goalActions: goalActions,
    );
    return report;
  }

  @override
  Future<MatchSportReport> attachPlayer({
    required String matchId,
    String? seasonPlayerId,
    String? guestPlayerId,
    String? firstName,
    String? lastName,
    bool isGoalkeeper = false,
    String? reason,
  }) async =>
      report;
}
