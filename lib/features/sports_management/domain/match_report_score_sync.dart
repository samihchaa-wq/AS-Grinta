import 'package:as_grinta/features/sports_management/domain/match_goal_action.dart';

/// Le score et la liste des buts ne peuvent jamais diverger.
///
/// Un 4–2 veut dire exactement quatre buts d'AS Grinta et deux buts adverses
/// dans la chronologie. Ces fonctions traduisent un changement de score en
/// changement de faits : ajouter un but à compléter quand le score monte,
/// demander lequel supprimer quand il descend.

/// Ce qu'un changement de score implique sur les faits du match.
class MatchScoreChangePlan {
  const MatchScoreChangePlan({
    required this.asGrintaToRemove,
    required this.opponentToRemove,
    required this.asGrintaToAdd,
    required this.opponentToAdd,
  });

  /// Nombre de buts d'AS Grinta que l'administrateur doit désigner.
  final int asGrintaToRemove;

  /// Nombre de buts adverses que l'administrateur doit désigner.
  final int opponentToRemove;
  final int asGrintaToAdd;
  final int opponentToAdd;

  bool get needsChoice => asGrintaToRemove > 0 || opponentToRemove > 0;
  bool get isEmpty =>
      asGrintaToRemove == 0 &&
      opponentToRemove == 0 &&
      asGrintaToAdd == 0 &&
      opponentToAdd == 0;
}

/// Compare le score visé aux faits déjà enregistrés.
MatchScoreChangePlan planScoreChange({
  required List<MatchGoalAction> goalActions,
  required int scoreAsGrinta,
  required int scoreAdverse,
}) {
  final currentAsGrinta = countGoals(goalActions, MatchGoalTeamSide.asGrinta);
  final currentOpponent = countGoals(goalActions, MatchGoalTeamSide.opponent);
  return MatchScoreChangePlan(
    asGrintaToRemove: (currentAsGrinta - scoreAsGrinta).clamp(0, 99),
    opponentToRemove: (currentOpponent - scoreAdverse).clamp(0, 99),
    asGrintaToAdd: (scoreAsGrinta - currentAsGrinta).clamp(0, 99),
    opponentToAdd: (scoreAdverse - currentOpponent).clamp(0, 99),
  );
}

int countGoals(List<MatchGoalAction> goalActions, MatchGoalTeamSide side) {
  return goalActions.where((goal) => goal.teamSide == side).length;
}

/// Ajoute les buts manquants, à compléter par l'administrateur : minute
/// inconnue, buteur non attribué, passe non attribuée.
///
/// Ne supprime jamais rien : une baisse de score passe obligatoirement par
/// [removeGoals], donc par un choix explicite.
List<MatchGoalAction> addMissingGoals({
  required List<MatchGoalAction> goalActions,
  required MatchScoreChangePlan plan,
  required int Function() nextLocalKey,
}) {
  if (plan.asGrintaToAdd == 0 && plan.opponentToAdd == 0) return goalActions;
  return [
    ...goalActions,
    for (var index = 0; index < plan.asGrintaToAdd; index += 1)
      MatchGoalAction.blank(
        localKey: 'new-${nextLocalKey()}',
        teamSide: MatchGoalTeamSide.asGrinta,
      ),
    for (var index = 0; index < plan.opponentToAdd; index += 1)
      MatchGoalAction.blank(
        localKey: 'new-${nextLocalKey()}',
        teamSide: MatchGoalTeamSide.opponent,
      ),
  ];
}

List<MatchGoalAction> removeGoals({
  required List<MatchGoalAction> goalActions,
  required Set<String> localKeys,
}) {
  return [
    for (final goal in goalActions)
      if (!localKeys.contains(goal.localKey)) goal,
  ];
}

/// Retire un joueur de toutes les attributions sans toucher aux buts eux-mêmes.
List<MatchGoalAction> detachParticipant({
  required List<MatchGoalAction> goalActions,
  required String participantId,
}) {
  return [
    for (final goal in goalActions) goal.withoutParticipant(participantId),
  ];
}

/// Ordonne la chronologie : minutes connues d'abord, dans l'ordre, puis les
/// buts sans minute à leur place courante.
///
/// L'ordre saisi fait foi pour tout le reste : deux buts à la même minute, ou
/// sans minute, gardent la place que l'administrateur leur a donnée.
List<MatchGoalAction> sortChronologically(List<MatchGoalAction> goalActions) {
  final indexed = [
    for (var index = 0; index < goalActions.length; index += 1)
      (goal: goalActions[index], index: index),
  ];
  indexed.sort((a, b) {
    final minuteA = a.goal.minute;
    final minuteB = b.goal.minute;
    if (minuteA != null && minuteB != null && minuteA != minuteB) {
      return minuteA.compareTo(minuteB);
    }
    // Une minute inconnue ne remonte jamais devant une minute connue plus
    // petite : elle reste simplement à sa place dans la liste.
    return a.index.compareTo(b.index);
  });
  return [for (final row in indexed) row.goal];
}

/// Déplace un but dans la liste. C'est le réordonnancement manuel.
///
/// [newIndex] est la place finale du but, une fois retiré de son ancienne
/// position — la même convention que `ReorderableListView.onReorderItem`.
List<MatchGoalAction> moveGoal({
  required List<MatchGoalAction> goalActions,
  required int oldIndex,
  required int newIndex,
}) {
  if (oldIndex < 0 || oldIndex >= goalActions.length) return goalActions;
  final next = [...goalActions];
  final goal = next.removeAt(oldIndex);
  next.insert(newIndex.clamp(0, next.length), goal);
  return next;
}

/// Message d'erreur si les faits du match ne sont pas validables, sinon `null`.
String? validateGoalActions({
  required List<MatchGoalAction> goalActions,
  required int scoreAsGrinta,
  required int scoreAdverse,
  required Set<String> squadParticipantIds,
}) {
  if (countGoals(goalActions, MatchGoalTeamSide.asGrinta) != scoreAsGrinta ||
      countGoals(goalActions, MatchGoalTeamSide.opponent) != scoreAdverse) {
    return 'Le score ne correspond pas à la liste des buts.';
  }
  for (final goal in goalActions) {
    final minute = goal.minute;
    if (minute != null && (minute < 0 || minute > kMatchGoalMaxMinute)) {
      return 'Une minute doit être comprise entre 0 et $kMatchGoalMaxMinute.';
    }
    if (goal.scorerParticipantId != null &&
        !squadParticipantIds.contains(goal.scorerParticipantId)) {
      return 'Un buteur ne fait plus partie de l’effectif du match.';
    }
    if (goal.assistParticipantId != null &&
        !squadParticipantIds.contains(goal.assistParticipantId)) {
      return 'Un passeur ne fait plus partie de l’effectif du match.';
    }
    if (goal.assistParticipantId != null &&
        goal.assistParticipantId == goal.scorerParticipantId) {
      return 'Un joueur ne peut pas être son propre passeur.';
    }
    if (goal.assistParticipantId != null && goal.scorerParticipantId == null) {
      return 'Une passe décisive suppose un buteur.';
    }
    if (goal.isOwnGoal && goal.assistParticipantId != null) {
      return 'Un contre-son-camp ne peut pas porter de passe décisive.';
    }
  }
  return null;
}
