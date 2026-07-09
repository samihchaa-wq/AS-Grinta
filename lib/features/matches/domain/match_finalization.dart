class MatchGoal {
  const MatchGoal({
    required this.team,
    required this.minute,
    required this.scorerId,
    required this.assisterId,
  });

  final String team;
  final int minute;
  final String? scorerId;
  final String? assisterId;
}

class MatchSubstitution {
  const MatchSubstitution({
    required this.minute,
    required this.inPlayerId,
    required this.outPlayerId,
  });

  final int minute;
  final String inPlayerId;
  final String outPlayerId;
}

class MatchFinalizationValidation {
  const MatchFinalizationValidation({
    required this.isValid,
    required this.issues,
  });

  final bool isValid;
  final List<String> issues;
}

class MatchFinalizationRules {
  static MatchFinalizationValidation validate({
    required int? grintaScore,
    required int? opponentScore,
    required List<MatchGoal> goals,
    required List<MatchSubstitution> substitutions,
  }) {
    final issues = <String>[];

    if (grintaScore == null || opponentScore == null) {
      issues.add('Le score final doit être renseigné.');
    } else if (grintaScore < 0 || opponentScore < 0) {
      issues.add('Le score final ne peut pas être négatif.');
    }

    for (final goal in goals) {
      if (goal.minute < 0 || goal.minute > 100) {
        issues.add('Chaque but doit avoir une minute comprise entre 0 et 100.');
        break;
      }
      if (goal.team != 'grinta' && goal.team != 'adversaire') {
        issues.add('Chaque but doit appartenir à une équipe valide.');
        break;
      }
    }

    final grintaGoals = goals.where((goal) => goal.team == 'grinta').length;
    final opponentGoals = goals.where((goal) => goal.team == 'adversaire').length;

    if (grintaScore != null &&
        opponentScore != null &&
        (grintaGoals != grintaScore || opponentGoals != opponentScore)) {
      issues.add('Le score ne correspond pas au nombre de buts enregistrés.');
    }

    for (final substitution in substitutions) {
      if (substitution.minute < 0 || substitution.minute > 100) {
        issues.add('Chaque remplacement doit avoir une minute comprise entre 0 et 100.');
        break;
      }
      if (substitution.inPlayerId == substitution.outPlayerId) {
        issues.add('Un joueur ne peut pas entrer et sortir sur le même remplacement.');
        break;
      }
    }

    return MatchFinalizationValidation(
      isValid: issues.isEmpty,
      issues: issues,
    );
  }

  static double calculatePoints({
    required double odds,
    required int predictedGrintaScore,
    required int predictedOpponentScore,
    required int actualGrintaScore,
    required int actualOpponentScore,
  }) {
    final isExactScore = predictedGrintaScore == actualGrintaScore &&
        predictedOpponentScore == actualOpponentScore;
    if (isExactScore) {
      return odds * 15;
    }

    final predictedResult = _result(
      predictedGrintaScore,
      predictedOpponentScore,
    );
    final actualResult = _result(
      actualGrintaScore,
      actualOpponentScore,
    );

    if (predictedResult == actualResult) {
      return odds * 10;
    }

    return 0.0;
  }

  static String resultKey(int grintaScore, int opponentScore) {
    return _result(grintaScore, opponentScore);
  }

  static String _result(int grintaScore, int opponentScore) {
    if (grintaScore > opponentScore) return 'win';
    if (grintaScore < opponentScore) return 'loss';
    return 'draw';
  }
}
