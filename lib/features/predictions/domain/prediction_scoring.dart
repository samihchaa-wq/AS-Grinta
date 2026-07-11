/// Barème des pronostics de match, identique à la vue SQL
/// v_match_prediction_points :
///   score exact                                   → cote × 20
///   bon vainqueur + bon écart de buts             → cote × 15
///   bon vainqueur + score exact d'une des équipes → cote × 15
///   bon vainqueur seul                            → cote × 10
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
      return baseOdds * 20;
    }
    if (predictedHome - predictedAway == actualHome - actualAway) {
      return baseOdds * 15;
    }
    if (predictedHome == actualHome || predictedAway == actualAway) {
      return baseOdds * 15;
    }
    return baseOdds * 10;
  }

  static int _result(int home, int away) {
    if (home > away) return 1;
    if (home == away) return 0;
    return -1;
  }
}
