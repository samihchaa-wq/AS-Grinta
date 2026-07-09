class PredictionScoring {
  const PredictionScoring._();

  static const double exactScoreMultiplier = 2.0;
  static const double correctGoalDifferenceMultiplier = 1.75;
  static const double oneTeamGoalsAndResultMultiplier = 1.5;
  static const double correctResultMultiplier = 1.0;

  static double multiplier({
    required int predictedHome,
    required int predictedAway,
    required int actualHome,
    required int actualAway,
  }) {
    final predictedResult = _result(predictedHome, predictedAway);
    final actualResult = _result(actualHome, actualAway);

    if (predictedResult != actualResult) return 0;

    if (predictedHome == actualHome && predictedAway == actualAway) {
      return exactScoreMultiplier;
    }

    final predictedDifference = predictedHome - predictedAway;
    final actualDifference = actualHome - actualAway;
    if (predictedDifference == actualDifference) {
      return correctGoalDifferenceMultiplier;
    }

    if (predictedHome == actualHome || predictedAway == actualAway) {
      return oneTeamGoalsAndResultMultiplier;
    }

    return correctResultMultiplier;
  }

  static double? points({
    required int predictedHome,
    required int predictedAway,
    required int actualHome,
    required int actualAway,
    required double? baseOdds,
  }) {
    if (baseOdds == null) return null;
    return baseOdds * 10 * multiplier(
      predictedHome: predictedHome,
      predictedAway: predictedAway,
      actualHome: actualHome,
      actualAway: actualAway,
    );
  }

  static int _result(int home, int away) {
    if (home > away) return 1;
    if (home == away) return 0;
    return -1;
  }
}
