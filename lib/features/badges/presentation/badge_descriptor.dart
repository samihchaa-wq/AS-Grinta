/// Ce qu'un emblème annonce sous son illustration : le critère mesuré, et la
/// temporalité sur laquelle il l'est. Les deux tiennent sur deux lignes
/// distinctes du socle, jamais sur une seule.
class BadgeDescriptor {
  const BadgeDescriptor(this.label, [this.period]);

  /// Le critère : `BUTS`, `MATCHS`, `TRIPLÉ`, `BALLON D’OR`…
  final String label;

  /// La temporalité : `SAISON`, `CARRIÈRE`… `null` quand le critère se suffit
  /// à lui-même (un exploit n'a pas de période).
  final String? period;
}

BadgeDescriptor badgeDescriptorFor({
  String? code,
  String? metric,
  String? category,
}) {
  final raw = _rawDescriptorFor(code: code, metric: metric, category: category);
  final parts = raw.split(' · ');
  if (parts.length == 2) return BadgeDescriptor(parts.first, parts.last);
  return BadgeDescriptor(raw);
}

String _rawDescriptorFor({
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
      return 'TRAÎTRE';
    case 'title_most_present':
      return 'MONSIEUR PRÉSENT · SAISON';
    case 'title_top_scorer':
      return 'SOULIER D’OR · SAISON';
    case 'title_best_winrate':
      return 'MONSIEUR VICTOIRE · SAISON';
    case 'title_mvp_king':
      return 'BALLON D’OR · SAISON';
    case 'title_best_pred_player':
      return 'L’ANALYSTE · SAISON';
    case 'title_best_pred_match':
      return 'LE VISIONNAIRE · SAISON';
    case 'title_best_pred_overall':
      return 'LE CERVEAU · SAISON';
  }
  switch (code) {
    case 'exploit_remplace_gardien':
      return 'GARDIEN D’UN SOIR';
    case 'exploit_penalty_provoque':
      return 'LE BOUCHER';
    case 'exploit_penalty_subi':
      return 'LE PLONGEUR';
    case 'exploit_but_vainqueur_tardif':
      return 'CLUTCH';
    case 'exploit_csc':
      return 'LA BOULETTE';
    case 'role_president':
      return 'EL PRESIDENTE';
    case 'role_coach':
      return 'COACH';
    case 'role_goalkeeper':
      return 'GARDIEN';
  }
  if (category == 'palmares') return 'PALMARÈS';
  if (category == 'faits_de_jeu') return 'FAIT DE JEU';
  if (category == 'pronos_all_time') return 'PRONOSTIC · CARRIÈRE';
  return 'BADGE';
}
