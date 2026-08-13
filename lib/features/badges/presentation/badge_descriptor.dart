String badgeDescriptorFor({
  String? code,
  String? metric,
  String? category,
}) {
  switch (metric) {
    case 'matches_played_season':
      return 'MATCHS · SAISON';
    case 'matches_played':
      return 'MATCHS · CARRIÈRE';
    case 'goals_season':
      return 'BUTS · SAISON';
    case 'goals':
      return 'BUTS · CARRIÈRE';
    case 'wins_season':
      return 'VICTOIRES · SAISON';
    case 'wins':
      return 'VICTOIRES · CARRIÈRE';
    case 'clean_sheets_season':
      return 'CLEAN SHEETS · SAISON';
    case 'clean_sheets':
      return 'CLEAN SHEETS · CARRIÈRE';
    case 'mvp':
      return 'HDM · CARRIÈRE';
    case 'max_match_goals':
      if (code == 'max_match_goals__3') return 'TRIPLÉ';
      if (code == 'max_match_goals__4') return 'QUADRUPLÉ';
      if (code == 'max_match_goals__5') return 'QUINTUPLÉ';
      return 'EXPLOIT BUTEUR';
    case 'bet_against_grinta':
      return 'PRONOSTIC SPÉCIAL';
    case 'title_most_present':
      return 'MONSIEUR PRÉSENT';
    case 'title_top_scorer':
      return 'SOULIER D’OR';
    case 'title_best_winrate':
      return 'MONSIEUR VICTOIRE';
    case 'title_mvp_king':
      return 'BALLON D’OR';
    case 'title_best_pred_player':
      return 'L’ANALYSTE';
    case 'title_best_pred_match':
      return 'LE VISIONNAIRE';
    case 'title_best_pred_overall':
      return 'LE CERVEAU';
  }
  switch (code) {
    case 'exploit_remplace_gardien':
      return 'GARDIEN D’UN SOIR';
    case 'exploit_penalty_provoque':
      return 'LE BOUCHER';
    case 'exploit_penalty_subi':
      return 'LE PLONGEUR';
    case 'exploit_penalty_arrete':
      return 'GOALKEEPER';
    case 'exploit_but_vainqueur_tardif':
      return 'CLUTCH';
    case 'exploit_csc':
      return 'LA BOULETTE';
    case 'role_president':
      return 'EL PRESIDENTE';
    case 'role_coach':
      return 'COACH';
  }
  if (category == 'palmares') return 'PALMARÈS';
  if (category == 'faits_de_jeu') return 'FAIT DE JEU';
  if (category == 'pronos_all_time') return 'PRONOSTIC';
  return 'BADGE';
}
