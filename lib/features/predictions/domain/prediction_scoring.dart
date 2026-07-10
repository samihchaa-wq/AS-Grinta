class PredictionScoring {
  const PredictionScoring._();

  static double? points({
    required int predictedHome,
    required int predictedAway,
    required int actualHome,
    required int actualAway,
    required double? baseOdds,
  }) {
    if (baseOdds == null) return null;

    if (predictedHome == actualHome && predictedAway == actualAway) {
      return baseOdds * 15;
    }

    final predictedResult = _result(predictedHome, predictedAway);
    final actualResult = _result(actualHome, actualAway);
    if (predictedResult == actualResult) {
      return baseOdds * 10;
    }

    return 0;
  }

  static int _result(int home, int away) {
    if (home > away) return 1;
    if (home == away) return 0;
    return -1;
  }
}
