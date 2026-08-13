import 'package:flutter/material.dart';

const Color kDefaultBadgeColor = Color(0xFF3A4568);
const Color kDiamondBadgeColor = Color(0xFFB9F2FF);

Color? parseBadgeColor(String? hex) {
  if (hex == null) return null;
  var value = hex.trim().replaceAll('#', '');
  if (value.length == 6) value = 'FF$value';
  if (value.length != 8) return null;
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? null : Color(parsed);
}

List<Color> _badgeSurfaceColors(Color base) {
  switch (base.toARGB32()) {
    case 0xFF7A858D:
    case 0xFF6E7A86:
      return const [Color(0xFFE2E6E8), Color(0xFF9AA4AA), Color(0xFF5F686E), Color(0xFFB9C0C4), Color(0xFF747E84)];
    case 0xFFCD7F32:
    case 0xFFB87333:
      return const [Color(0xFFF2C17D), Color(0xFFD59047), Color(0xFF8A4B20), Color(0xFFE0A15A), Color(0xFFA95E2B)];
    case 0xFFC0C0C0:
    case 0xFFC4CBD4:
      return const [Color(0xFFFAFAFA), Color(0xFFD8DADD), Color(0xFF8B9299), Color(0xFFECEDEF), Color(0xFFAEB3B8)];
    case 0xFFD4AF37:
    case 0xFFE3B23C:
      return const [Color(0xFFFFF1A6), Color(0xFFE5C04B), Color(0xFFA77B00), Color(0xFFF7D76F), Color(0xFFC59B19)];
    case 0xFFB9F2FF:
    case 0xFF5FC9D9:
      return const [Color(0xFFF3FDFF), Color(0xFFC9F6FF), Color(0xFF71D7E7), Color(0xFFDDFBFF), Color(0xFF91DCE8)];
  }
  return [
    Color.lerp(base, Colors.white, 0.36)!,
    Color.lerp(base, Colors.white, 0.08)!,
    Color.lerp(base, Colors.black, 0.22)!,
    Color.lerp(base, Colors.white, 0.15)!,
    Color.lerp(base, Colors.black, 0.08)!,
  ];
}

String? baremeLabelFor(String? metric, int? threshold) {
  if (metric == null || threshold == null) return null;
  if (metric == 'max_match_goals' ||
      metric == 'seasons_complete' ||
      metric == 'bet_against_grinta' ||
      metric.startsWith('title_')) {
    return null;
  }
  return '$threshold';
}

bool isCareerBadgeCategory(String? category) =>
    category == 'joueur_all_time' || category == 'pronos_all_time';

String badgeDescriptorFor({String? code, String? metric, String? category}) {
  switch (metric) {
    case 'matches_played_season': return 'MATCHS · SAISON';
    case 'matches_played': return 'MATCHS · CARRIÈRE';
    case 'goals_season': return 'BUTS · SAISON';
    case 'goals': return 'BUTS · CARRIÈRE';
    case 'wins_season': return 'VICTOIRES · SAISON';
    case 'wins': return 'VICTOIRES · CARRIÈRE';
    case 'clean_sheets_season': return 'CLEAN SHEETS · SAISON';
    case 'clean_sheets': return 'CLEAN SHEETS · CARRIÈRE';
    case 'mvp': return 'HDM · CARRIÈRE';
    case 'max_match_goals':
      if (code == 'max_match_goals__3') return 'TRIPLÉ';
      if (code == 'max_match_goals__4') return 'QUADRUPLÉ';
      if (code == 'max_match_goals__5') return 'QUINTUPLÉ';
      return 'EXPLOIT BUTEUR';
    case 'bet_against_grinta': return 'PRONOSTIC SPÉCIAL';
    case 'title_most_present': return 'MONSIEUR PRÉSENT';
    case 'title_top_scorer': return 'SOULIER D’OR';
    case 'title_best_winrate': return 'MONSIEUR VICTOIRE';
    case 'title_mvp_king': return 'BALLON D’OR';
    case 'title_best_pred_player': return 'L’ANALYSTE';
    case 'title_best_pred_match': return 'LE VISIONNAIRE';
    case 'title_best_pred_overall': return 'LE CERVEAU';
  }
  switch (code) {
    case 'exploit_remplace_gardien': return 'GARDIEN D’UN SOIR';
    case 'exploit_penalty_provoque': return 'LE BOUCHER';
    case 'exploit_penalty_subi': return 'LE PLONGEUR';
    case 'exploit_penalty_arrete': return 'GOALKEEPER';
    case 'exploit_but_vainqueur_tardif': return 'CLUTCH';
    case 'exploit_csc': return 'LA BOULETTE';
    case 'role_president': return 'EL PRESIDENTE';
    case 'role_coach': return 'COACH';
  }
  if (category == 'palmares') return 'PALMARÈS';
  if (category == 'faits_de_jeu') return 'FAIT DE JEU';
  if (category == 'pronos_all_time') return 'PRONOSTIC';
  return 'BADGE';
}

List<Shadow> _emojiOutline(double fontSize) {
  final o = fontSize * 0.04;
  return [
    for (final dir in const [Offset(-1,-1), Offset(1,-1), Offset(-1,1), Offset(1,1), Offset(0,-1), Offset(0,1), Offset(-1,0), Offset(1,0)])
      Shadow(color: const Color(0xF0000000), blurRadius: fontSize * 0.015, offset: dir * o),
  ];
}

class BadgeEmblem extends StatelessWidget {
  const BadgeEmblem({
    super.key,
    required this.emoji,
    required this.size,
    this.imageUrl,
    this.color,
    this.baremeLabel,
    this.descriptor,
    this.showStar = false,
    this.starCount = 1,
    this.starsMultiplyBareme = false,
    this.starOverflow = false,
  });

  final String emoji;
  final double size;
  final String? imageUrl;
  final String? color;
  final String? baremeLabel;
  final String? descriptor;
  final bool showStar;
  final bool starsMultiplyBareme;
  final bool starOverflow;
  final int starCount;

  @override
  Widget build(BuildContext context) {
    final base = parseBadgeColor(color) ?? kDefaultBadgeColor;
    final emblem = _body(base);
    if (!showStar) return emblem;
    final overhang = size * .13;
    final stars = SizedBox(
      width: size,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < (starCount < 1 ? 1 : starCount); i++)
              Icon(Icons.star_rounded, size: size * .20, color: const Color(0xFFFCC21B)),
          ],
        ),
      ),
    );
    if (starOverflow) {
      return Stack(clipBehavior: Clip.none, children: [emblem, Positioned(left: 0, right: 0, top: -overhang, child: stars)]);
    }
    return Padding(
      padding: EdgeInsets.only(top: overhang),
      child: Stack(clipBehavior: Clip.none, children: [emblem, Positioned(left: 0, right: 0, top: -overhang, child: stars)]),
    );
  }

  Widget _body(Color base) {
    final hasMedal = baremeLabel != null && baremeLabel!.trim().isNotEmpty;
    final artH = size * .82;
    final footerH = size * .32;
    final medal = size * .32;
    final overlap = hasMedal ? medal * .42 : 0.0;
    return SizedBox(
      width: size,
      height: artH + footerH - overlap,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          _art(base, artH),
          Positioned(left: 0, right: 0, top: artH - overlap, child: _footer(base, footerH, hasMedal)),
          if (hasMedal) Positioned(top: artH - medal * .56, child: _medal(base, medal)),
        ],
      ),
    );
  }

  Widget _art(Color base, double height) {
    final radius = size * .20;
    return Container(
      width: size,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius), bottom: Radius.circular(size * .10)),
        gradient: LinearGradient(begin: const Alignment(-1,-.95), end: const Alignment(1,.95), colors: _badgeSurfaceColors(base), stops: const [0,.28,.52,.72,1]),
        border: Border.all(color: Color.lerp(base, Colors.black, .32)!, width: size * .035),
        boxShadow: [BoxShadow(color: const Color(0x42000000), blurRadius: size * .08, offset: Offset(0, size * .035))],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (base.toARGB32() == kDiamondBadgeColor.toARGB32()) _diamondPattern(height),
          if (imageUrl != null)
            Image.network(imageUrl!, width: size * .72, height: height * .72, fit: BoxFit.contain, filterQuality: FilterQuality.high, errorBuilder: (_, __, ___) => _emoji())
          else
            _emoji(),
        ],
      ),
    );
  }

  Widget _footer(Color base, double height, bool hasMedal) {
    final label = descriptor?.trim().isNotEmpty == true
        ? descriptor!.trim()
        : (showStar ? 'PALMARÈS' : hasMedal ? 'PERFORMANCE' : 'EXPLOIT');
    return Container(
      height: height,
      alignment: Alignment.center,
      padding: EdgeInsets.fromLTRB(size * .05, hasMedal ? size * .075 : size * .025, size * .05, size * .02),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1D40),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(size * .17)),
        border: Border.all(color: Color.lerp(base, Colors.white, .34)!, width: size * .018),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, maxLines: 1, style: TextStyle(color: Colors.white, fontSize: size * .11, height: 1, fontWeight: FontWeight.w900, letterSpacing: .3)),
      ),
    );
  }

  Widget _medal(Color base, double d) {
    return Container(
      width: d,
      height: d,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [Color.lerp(base, Colors.white, .56)!, base, Color.lerp(base, Colors.black, .30)!], stops: const [0,.62,1]),
        border: Border.all(color: Colors.white.withValues(alpha: .88), width: size * .018),
        boxShadow: [BoxShadow(color: const Color(0x66000000), blurRadius: size * .05, offset: Offset(0, size * .02))],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: EdgeInsets.all(size * .035),
          child: Text(baremeLabel!, style: TextStyle(color: Colors.white, fontSize: size * .20, height: 1, fontWeight: FontWeight.w900)),
        ),
      ),
    );
  }

  Widget _emoji() {
    final font = size * .49;
    return Text(emoji, style: TextStyle(fontSize: font, shadows: _emojiOutline(font)));
  }

  Widget _diamondPattern(double height) {
    final diamond = Text('💎', style: TextStyle(fontSize: size * .10, height: 1));
    const spots = [Alignment(-.78,-.70), Alignment(.78,-.70), Alignment(-.78,.70), Alignment(.78,.70), Alignment(0,-.88), Alignment(0,.88)];
    return SizedBox(width: size, height: height, child: Stack(children: [for (final a in spots) Align(alignment: a, child: diamond)]));
  }
}
