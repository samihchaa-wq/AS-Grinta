/// Barème des pronostics de match, identique à la vue SQL
/// v_match_prediction_points :
///   score exact                                   → cote × 2
///   bon vainqueur + bon écart de buts             → cote × 1,5
///   bon vainqueur + score exact d'une des équipes → cote × 1,5
///   bon vainqueur seul                            → cote × 1
///   mauvais vainqueur ou pronostic non rempli     → 0
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

    final predictedResult = _result(predictedHome, predictedAway);
    final actualResult = _result(actualHome, actualAway);
    if (predictedResult != actualResult) return 0;

    if (predictedHome == actualHome && predictedAway == actualAway) {
      return baseOdds * 2;
    }
    if (predictedHome - predictedAway == actualHome - actualAway) {
      return baseOdds * 1.5;
    }
    if (predictedHome == actualHome || predictedAway == actualAway) {
      return baseOdds * 1.5;
    }
    return baseOdds * 1;
  }

  static int _result(int home, int away) {
    if (home > away) return 1;
    if (home == away) return 0;
    return -1;
  }
}
