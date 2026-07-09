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
  const MatchFinalizationValidation({required this.isValid, required this.issues});

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
    }

    final grintaGoals = goals.where((goal) => goal.team == 'grinta').length;
    final opponentGoals = goals.where((goal) => goal.team == 'adversaire').length;

    if (grintaScore != null && opponentScore != null && (grintaGoals != grintaScore || opponentGoals != opponentScore)) {
      issues.add('Le score ne correspond pas au nombre de buts enregistrés.');
    }

    return MatchFinalizationValidation(isValid: issues.isEmpty, issues: issues);
  }

  static double calculatePoints({
    required double odds,
    required int grintaScore,
    required int opponentScore,
    int? actualGrintaScore,
    int? actualOpponentScore,
  }) {
    if (grintaScore == 1 && opponentScore == 0) {
      return odds * 15;
    }

    final actualResult = actualGrintaScore != null && actualOpponentScore != null
        ? _result(actualGrintaScore, actualOpponentScore)
        : null;
    final predictedResult = _result(grintaScore, opponentScore);

    if (actualResult != null && predictedResult == actualResult) {
      return odds * 10;
    }

    if (grintaScore == opponentScore) {
      return odds * 10;
    }

    return 0.0;
  }

  static String _result(int grintaScore, int opponentScore) {
    if (grintaScore > opponentScore) return 'win';
    if (grintaScore < opponentScore) return 'loss';
    return 'draw';
  }
}
