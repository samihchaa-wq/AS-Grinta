import 'package:as_grinta/features/sports_management/domain/match_goal_action.dart';
import 'package:as_grinta/features/sports_management/domain/match_report_score_sync.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les faits du match : un but porte son buteur ET son passeur, le score ne
/// peut jamais s'en écarter, et une attribution impossible n'est jamais
/// enregistrée.
void main() {
  MatchGoalAction ours(String key) => MatchGoalAction.blank(
        localKey: key,
        teamSide: MatchGoalTeamSide.asGrinta,
      );
  MatchGoalAction theirs(String key) => MatchGoalAction.blank(
        localKey: key,
        teamSide: MatchGoalTeamSide.opponent,
      );

  group('attribution d’un but', () {
    test('un but garde le lien exact buteur → passeur', () {
      final goal =
          ours('g1').withScorer('p1', 'Samih').withAssist('p2', 'Nabil');

      expect(goal.scorerParticipantId, 'p1');
      expect(goal.assistParticipantId, 'p2');
      expect(goal.assistKind, MatchGoalAssistKind.player);
    });

    test('un joueur ne peut pas être son propre passeur', () {
      final goal =
          ours('g1').withScorer('p1', 'Samih').withAssist('p1', 'Samih');

      expect(goal.assistParticipantId, isNull);
    });

    test('changer de buteur pour le passeur libère la passe', () {
      final goal = ours('g1')
          .withScorer('p1', 'Samih')
          .withAssist('p2', 'Nabil')
          .withScorer('p2', 'Nabil');

      expect(goal.scorerParticipantId, 'p2');
      expect(goal.assistParticipantId, isNull);
      expect(goal.assistKind, MatchGoalAssistKind.unknown);
    });

    test('« aucune passe » et « passe inconnue » restent distincts', () {
      final withoutAssist = ours('g1').withScorer('p1', 'Samih').withNoAssist();
      final unknownAssist =
          ours('g2').withScorer('p1', 'Samih').withUnknownAssist();

      expect(withoutAssist.assistKind, MatchGoalAssistKind.none);
      expect(unknownAssist.assistKind, MatchGoalAssistKind.unknown);
      expect(withoutAssist.assistParticipantId, isNull);
      expect(unknownAssist.assistParticipantId, isNull);
    });

    test('un buteur inconnu est autorisé et efface la passe', () {
      final goal = ours('g1')
          .withScorer('p1', 'Samih')
          .withAssist('p2', 'Nabil')
          .withUnknownScorer();

      expect(goal.hasUnknownScorer, isTrue);
      expect(goal.assistParticipantId, isNull);
      expect(goal.isOwnGoal, isFalse);
    });

    test('un CSC adverse n’a ni buteur ni passeur', () {
      final goal = ours('g1')
          .withScorer('p1', 'Samih')
          .withAssist('p2', 'Nabil')
          .withOwnGoal();

      expect(goal.isOwnGoal, isTrue);
      expect(goal.scorerParticipantId, isNull);
      expect(goal.assistParticipantId, isNull);
      expect(goal.assistKind, MatchGoalAssistKind.none);
      expect(goal.canCarryAssist, isFalse);
    });

    test('un CSC AS Grinta est un but adverse sans passeur possible', () {
      final goal = theirs('g1').withOwnGoal();

      expect(goal.isAsGrinta, isFalse);
      expect(goal.isOwnGoal, isTrue);
      expect(goal.canCarryAssist, isFalse);
    });

    test('un but adverse ne peut jamais porter de passeur', () {
      final goal = theirs('g1').withAssist('p2', 'Nabil');

      expect(goal.assistParticipantId, isNull);
    });

    test('une passe sans buteur est refusée', () {
      final goal = ours('g1').withAssist('p2', 'Nabil');

      expect(goal.assistParticipantId, isNull);
    });
  });

  group('minutes', () {
    test('la minute est facultative', () {
      expect(ours('g1').minute, isNull);
      expect(ours('g1').withMinute(30).withMinute(null).minute, isNull);
    });

    test('les minutes 0 et 90 sont acceptées', () {
      final issue = validateGoalActions(
        goalActions: [ours('g1').withMinute(0), ours('g2').withMinute(90)],
        scoreAsGrinta: 2,
        scoreAdverse: 0,
        squadParticipantIds: const {},
      );

      expect(issue, isNull);
    });

    test('une minute hors de 0–90 est rejetée', () {
      for (final minute in [-1, 91, 120]) {
        final issue = validateGoalActions(
          goalActions: [ours('g1').withMinute(minute)],
          scoreAsGrinta: 1,
          scoreAdverse: 0,
          squadParticipantIds: const {},
        );
        expect(issue, isNotNull, reason: 'minute $minute doit être refusée');
      }
    });
  });

  group('score et faits du match liés', () {
    test('le score qui monte crée des buts à compléter', () {
      var seed = 0;
      final goals = [ours('g1'), ours('g2'), ours('g3'), theirs('o1')];

      final plan = planScoreChange(
        goalActions: goals,
        scoreAsGrinta: 4,
        scoreAdverse: 1,
      );
      final next = addMissingGoals(
        goalActions: goals,
        plan: plan,
        nextLocalKey: () => seed++,
      );

      expect(countGoals(next, MatchGoalTeamSide.asGrinta), 4);
      expect(countGoals(next, MatchGoalTeamSide.opponent), 1);
      final created = next.last;
      expect(created.minute, isNull);
      expect(created.hasUnknownScorer, isTrue);
      expect(created.assistKind, MatchGoalAssistKind.unknown);
    });

    test('le score qui baisse ne supprime jamais tout seul', () {
      final goals = [ours('g1'), ours('g2'), ours('g3'), ours('g4')];

      final plan = planScoreChange(
        goalActions: goals,
        scoreAsGrinta: 3,
        scoreAdverse: 0,
      );

      expect(plan.needsChoice, isTrue);
      expect(plan.asGrintaToRemove, 1);
      // Rien n'a bougé tant que l'administrateur n'a pas choisi.
      expect(
        addMissingGoals(
          goalActions: goals,
          plan: plan,
          nextLocalKey: () => 0,
        ).length,
        4,
      );
    });

    test('4–2 vers 2–3 : deux buts à choisir et un but adverse créé', () {
      var seed = 0;
      final goals = [
        ours('g1'),
        ours('g2'),
        ours('g3'),
        ours('g4'),
        theirs('o1'),
        theirs('o2'),
      ];

      final plan = planScoreChange(
        goalActions: goals,
        scoreAsGrinta: 2,
        scoreAdverse: 3,
      );
      expect(plan.asGrintaToRemove, 2);
      expect(plan.opponentToAdd, 1);

      final afterRemoval = removeGoals(
        goalActions: goals,
        localKeys: {'g2', 'g4'},
      );
      final next = addMissingGoals(
        goalActions: afterRemoval,
        plan: plan,
        nextLocalKey: () => seed++,
      );

      expect(countGoals(next, MatchGoalTeamSide.asGrinta), 2);
      expect(countGoals(next, MatchGoalTeamSide.opponent), 3);
      expect(
        validateGoalActions(
          goalActions: next,
          scoreAsGrinta: 2,
          scoreAdverse: 3,
          squadParticipantIds: const {},
        ),
        isNull,
      );
    });

    test('un score incohérent avec les buts est refusé', () {
      final issue = validateGoalActions(
        goalActions: [ours('g1'), ours('g2')],
        scoreAsGrinta: 3,
        scoreAdverse: 0,
        squadParticipantIds: const {},
      );

      expect(issue, 'Le score ne correspond pas à la liste des buts.');
    });
  });

  group('joueur retiré du compte rendu', () {
    test('ses attributions deviennent non attribuées sans perdre le but', () {
      final goals = [
        ours('g1').withScorer('p1', 'Samih').withAssist('p2', 'Nabil'),
        ours('g2').withScorer('p3', 'Karim').withAssist('p1', 'Samih'),
      ];

      final next = detachParticipant(goalActions: goals, participantId: 'p1');

      expect(next.length, 2, reason: 'les buts restent au score');
      expect(next[0].hasUnknownScorer, isTrue);
      expect(next[0].assistParticipantId, isNull);
      expect(next[1].scorerParticipantId, 'p3');
      expect(next[1].assistParticipantId, isNull);
      expect(next[1].assistKind, MatchGoalAssistKind.unknown);
    });

    test('un buteur hors de l’effectif bloque la validation', () {
      final issue = validateGoalActions(
        goalActions: [ours('g1').withScorer('p1', 'Samih')],
        scoreAsGrinta: 1,
        scoreAdverse: 0,
        squadParticipantIds: const {'p2'},
      );

      expect(issue, 'Un buteur ne fait plus partie de l’effectif du match.');
    });
  });

  group('ordre de la chronologie', () {
    test('les minutes connues se rangent dans l’ordre', () {
      final sorted = sortChronologically([
        ours('g1').withMinute(51),
        ours('g2').withMinute(12),
        ours('g3').withMinute(34),
      ]);

      expect([for (final goal in sorted) goal.minute], [12, 34, 51]);
    });

    test('une minute inconnue garde sa place au lieu de remonter en tête', () {
      final sorted = sortChronologically([
        ours('g1').withMinute(12),
        ours('g2'),
        ours('g3').withMinute(34),
      ]);

      expect([for (final goal in sorted) goal.localKey], ['g1', 'g2', 'g3']);
    });

    test('l’administrateur peut réordonner à la main', () {
      final moved = moveGoal(
        goalActions: [ours('g1'), ours('g2'), ours('g3')],
        oldIndex: 2,
        newIndex: 0,
      );

      expect([for (final goal in moved) goal.localKey], ['g3', 'g1', 'g2']);
    });
  });

  group('paquet envoyé au serveur', () {
    test('un but complet part avec son lien buteur/passeur', () {
      final json = ours('g1')
          .withMinute(12)
          .withScorer('p1', 'Samih')
          .withAssist('p2', 'Nabil')
          .toRpcJson();

      expect(json['minute'], 12);
      expect(json['team_side'], 'as_grinta');
      expect(json['scorer_participant_id'], 'p1');
      expect(json['assist_participant_id'], 'p2');
      expect(json['assist_kind'], 'player');
      expect(json['is_own_goal'], isFalse);
    });

    test('un but importé du Live garde sa trace d’origine', () {
      final goal = MatchGoalAction.fromJson({
        'id': 'goal-1',
        'ordinal': 0,
        'minute': 12,
        'team_side': 'as_grinta',
        'scorer_participant_id': 'p1',
        'scorer_name': 'Samih',
        'assist_participant_id': 'p2',
        'assist_name': 'Nabil',
        'assist_kind': 'player',
        'is_own_goal': false,
        'source': 'live',
        'source_live_event_id': 'event-1',
      }, 0);

      expect(goal.source, 'live');
      expect(goal.sourceLiveEventId, 'event-1');
      expect(goal.scorerName, 'Samih');
      expect(goal.assistName, 'Nabil');
      expect(goal.toRpcJson()['source_live_event_id'], 'event-1');
    });
  });
}
