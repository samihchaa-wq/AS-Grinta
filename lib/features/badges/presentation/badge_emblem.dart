import 'package:flutter/material.dart';

/// Couleur par défaut d'un emblème quand aucune n'est définie.
const Color kDefaultBadgeColor = Color(0xFF3A4568);

/// Couleur des badges « Diamant » : leur carré est parsemé de petits 💎.
const Color kDiamondBadgeColor = Color(0xFFB9F2FF);

/// Convertit une couleur hex (`#RRGGBB` ou `RRGGBB`) en [Color].
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
    // Acier — gris froid avec reflets clairs.
    case 0xFF7A858D:
    case 0xFF6E7A86:
      return const [
        Color(0xFFE2E6E8),
        Color(0xFF9AA4AA),
        Color(0xFF5F686E),
        Color(0xFFB9C0C4),
        Color(0xFF747E84),
      ];
    // Bronze — cuivre chaud, plus proche d'un vrai bronze.
    case 0xFFCD7F32:
    case 0xFFB87333:
      return const [
        Color(0xFFF2C17D),
        Color(0xFFD59047),
        Color(0xFF8A4B20),
        Color(0xFFE0A15A),
        Color(0xFFA95E2B),
      ];
    // Argent — contraste froid du métal poli.
    case 0xFFC0C0C0:
    case 0xFFC4CBD4:
      return const [
        Color(0xFFFAFAFA),
        Color(0xFFD8DADD),
        Color(0xFF8B9299),
        Color(0xFFECEDEF),
        Color(0xFFAEB3B8),
      ];
    // Or — jaune moins saturé, avec ombres ambrées.
    case 0xFFD4AF37:
    case 0xFFE3B23C:
      return const [
        Color(0xFFFFF1A6),
        Color(0xFFE5C04B),
        Color(0xFFA77B00),
        Color(0xFFF7D76F),
        Color(0xFFC59B19),
      ];
    // Diamant — blanc glacé et cyan cristallin.
    case 0xFFB9F2FF:
    case 0xFF5FC9D9:
      return const [
        Color(0xFFF3FDFF),
        Color(0xFFC9F6FF),
        Color(0xFF71D7E7),
        Color(0xFFDDFBFF),
        Color(0xFF91DCE8),
      ];
  }

  // Les autres familles (bleu, violet, noir, orange, rouge...) conservent
  // leur identité, avec davantage de profondeur et un léger effet glossy.
  return [
    Color.lerp(base, Colors.white, 0.36)!,
    Color.lerp(base, Colors.white, 0.08)!,
    Color.lerp(base, Colors.black, 0.22)!,
    Color.lerp(base, Colors.white, 0.15)!,
    Color.lerp(base, Colors.black, 0.08)!,
  ];
}

/// Le seuil à écrire en petit sur l'emblème d'un badge de barème (paliers de
/// stats). `null` pour les badges à palier unique, les titres, triplé, etc.
String? baremeLabelFor(String? metric, int? threshold) {
  if (metric == null || threshold == null || threshold <= 1) return null;
  if (metric == 'max_match_goals' ||
      metric == 'seasons_complete' ||
      metric.startsWith('title_')) {
    return null;
  }
  return '$threshold';
}

/// Vrai pour les paliers de CARRIÈRE (cumul total). C'est le seul cas où le
/// chiffre du badge est multiplié par le nombre d'étoiles (ex. 200 buts →
/// « 200 » + 2 étoiles). Les paliers saisonniers gardent leur chiffre fixe (le
/// nombre d'étoiles compte alors les saisons).
bool isCareerBadgeCategory(String? category) =>
    category == 'joueur_all_time' || category == 'pronos_all_time';

/// Contour blanc épais + fin liseré sombre pour détacher l'emoji de la couleur
/// du carré (quelle que soit cette couleur), avec une légère ombre portée.
List<Shadow> _emojiOutline(double fontSize) {
  final o = fontSize * 0.04;
  final blur = fontSize * 0.015;
  const black = Color(0xF0000000);
  return [
    for (final dir in const [
      Offset(-0.7, -0.7),
      Offset(0.7, -0.7),
      Offset(-0.7, 0.7),
      Offset(0.7, 0.7),
      Offset(0, -1),
      Offset(0, 1),
      Offset(-1, 0),
      Offset(1, 0),
    ])
      Shadow(color: black, blurRadius: blur, offset: dir * o),
  ];
}

/// Emblème d'un badge : carré aux bords arrondis, coloré, avec l'emoji (ou une
/// image) dedans. Le seuil du barème est écrit en petit dans un coin, et une
/// étoile est posée au-dessus du carré pour les paliers finaux et les titres.
class BadgeEmblem extends StatelessWidget {
  const BadgeEmblem({
    super.key,
    required this.emoji,
    required this.size,
    this.imageUrl,
    this.color,
    this.baremeLabel,
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
  final bool showStar;
  final bool starsMultiplyBareme;
  final bool starOverflow;
  final int starCount;

  @override
  Widget build(BuildContext context) {
    final base = parseBadgeColor(color) ?? kDefaultBadgeColor;

    if (!showStar) {
      return _square(base, size);
    }

    final stars = starCount < 1 ? 1 : starCount;
    final overhang = size * 0.14;
    final starRow = SizedBox(
      width: size,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topCenter,
        child: _starRow(stars),
      ),
    );

    if (starOverflow) {
      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _square(base, size),
            Positioned(left: 0, right: 0, top: -overhang, child: starRow),
          ],
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size + overhang,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Align(alignment: Alignment.bottomCenter, child: _square(base, size)),
          Align(alignment: Alignment.topCenter, child: starRow),
        ],
      ),
    );
  }

  Widget _starRow(int stars) {
    final starSize = size * 0.22;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < stars; i++)
          Icon(
            Icons.star_rounded,
            size: starSize,
            color: const Color(0xFFFCC21B),
            shadows: [
              Shadow(
                color: const Color(0x73000000),
                blurRadius: starSize * 0.18,
                offset: Offset(0, starSize * 0.06),
              ),
            ],
          ),
      ],
    );
  }

  String? get _displayBareme {
    final label = baremeLabel;
    if (!starsMultiplyBareme || label == null || starCount <= 1) return label;
    final n = int.tryParse(label);
    if (n == null) return label;
    return (n * starCount).toString();
  }

  Widget _square(Color base, double sq) {
    final radius = sq * 0.26;
    final bareme = _displayBareme;
    final surfaceColors = _badgeSurfaceColors(base);
    return SizedBox(
      width: sq,
      height: sq,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: sq,
            height: sq,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: const Alignment(-1.0, -0.95),
                end: const Alignment(1.0, 0.95),
                colors: surfaceColors,
                stops: const [0.0, 0.28, 0.52, 0.72, 1.0],
              ),
              border: Border.all(
                color: Color.lerp(base, Colors.black, 0.32)!,
                width: sq * 0.045,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0x42000000),
                  blurRadius: sq * 0.09,
                  offset: Offset(0, sq * 0.04),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(radius),
                        gradient: const LinearGradient(
                          begin: Alignment(-1.0, -0.8),
                          end: Alignment(1.0, 0.8),
                          colors: [
                            Color(0x00FFFFFF),
                            Color(0x52FFFFFF),
                            Color(0x00FFFFFF),
                          ],
                          stops: [0.25, 0.46, 0.64],
                        ),
                      ),
                    ),
                  ),
                ),
                if (base.toARGB32() == kDiamondBadgeColor.toARGB32())
                  _diamondPattern(sq),
                if (imageUrl != null)
                  Image.network(
                    imageUrl!,
                    width: sq * 0.78,
                    height: sq * 0.78,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, __, ___) => _emoji(sq),
                  )
                else
                  _emoji(sq),
              ],
            ),
          ),
          if (bareme != null)
            Positioned(
              right: size * 0.02,
              bottom: size * 0.02,
              child: Container(
                width: size * 0.42,
                height: size * 0.30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1D40),
                  borderRadius: BorderRadius.circular(size * 0.11),
                  border: Border.all(
                    color: Color.lerp(base, Colors.white, 0.42)!,
                    width: size * 0.018,
                  ),
                ),
                child: Transform.translate(
                  offset: Offset(0, -size * 0.018),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: size * 0.045),
                      child: Text(
                        bareme,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: size * 0.24,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          foreground: Paint()..color = Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emoji(double sq) {
    final fontSize = sq * 0.55;
    return Text(
      emoji,
      style: TextStyle(fontSize: fontSize, shadows: _emojiOutline(fontSize)),
    );
  }

  Widget _diamondPattern(double sq) {
    final d = sq * 0.13;
    const spots = <Alignment>[
      Alignment(-0.82, -0.82),
      Alignment(0.82, -0.82),
      Alignment(-0.82, 0.82),
      Alignment(0.82, 0.82),
      Alignment(0.0, -0.94),
      Alignment(0.0, 0.94),
      Alignment(-0.94, 0.0),
      Alignment(0.94, 0.0),
    ];
    final diamond = Text(
      '💎',
      style: TextStyle(
        fontSize: d,
        height: 1,
        shadows: const [Shadow(color: Color(0x66000000), blurRadius: 1.5)],
      ),
    );
    return SizedBox(
      width: sq,
      height: sq,
      child: Stack(
        children: [
          for (final a in spots) Align(alignment: a, child: diamond),
        ],
      ),
    );
  }
}
