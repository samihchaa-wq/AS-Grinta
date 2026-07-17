import 'package:flutter/material.dart';

/// Couleur par défaut d'un emblème quand aucune n'est définie.
const Color kDefaultBadgeColor = Color(0xFF3A4568);

/// Couleur des badges « Diamant » : leur carré est parsemé de petits 💎.
const Color kDiamondBadgeColor = Color(0xFF5FC9D9);

/// Convertit une couleur hex (`#RRGGBB` ou `RRGGBB`) en [Color].
Color? parseBadgeColor(String? hex) {
  if (hex == null) return null;
  var value = hex.trim().replaceAll('#', '');
  if (value.length == 6) value = 'FF$value';
  if (value.length != 8) return null;
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? null : Color(parsed);
}

/// Le seuil à écrire en petit sur l'emblème d'un badge de barème (paliers de
/// stats). `null` pour les titres, triplé, etc. (emoji déjà unique).
String? baremeLabelFor(String? metric, int? threshold) {
  if (metric == null || threshold == null) return null;
  if (metric == 'max_match_goals' ||
      metric == 'seasons_complete' ||
      metric.startsWith('title_')) {
    return null;
  }
  return '$threshold';
}

/// Contour blanc épais + fin liseré sombre pour détacher l'emoji de la couleur
/// du carré (quelle que soit cette couleur), avec une légère ombre portée.
List<Shadow> _emojiOutline(double fontSize) {
  final d = fontSize * 0.06;
  final blur = fontSize * 0.03;
  const white = Colors.white;
  return [
    for (final o in const [
      Offset(-1, -1),
      Offset(1, -1),
      Offset(-1, 1),
      Offset(1, 1),
      Offset(0, -1.4),
      Offset(0, 1.4),
      Offset(-1.4, 0),
      Offset(1.4, 0),
    ])
      Shadow(color: white, blurRadius: blur, offset: o * d),
    Shadow(
      color: const Color(0xE6000000),
      blurRadius: fontSize * 0.05,
      offset: Offset(0, fontSize * 0.03),
    ),
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
  });

  final String emoji;
  final double size;
  final String? imageUrl;
  final String? color;
  final String? baremeLabel;
  final bool showStar;

  @override
  Widget build(BuildContext context) {
    final base = parseBadgeColor(color) ?? kDefaultBadgeColor;

    if (!showStar) {
      return _square(base, size);
    }

    // Le carré garde sa taille PLEINE ; une petite étoile se pose au-dessus.
    // La boîte est juste un peu plus haute (l'étoile chevauche le haut).
    final starSize = size * 0.20;
    final overhang = size * 0.14;
    return SizedBox(
      width: size,
      height: size + overhang,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Align(
            alignment: Alignment.bottomCenter,
            child: _square(base, size),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Text(
              '⭐',
              style: TextStyle(
                fontSize: starSize,
                height: 1,
                shadows: _emojiOutline(starSize),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _square(Color base, double sq) {
    final radius = sq * 0.26;
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
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(base, Colors.white, 0.22)!,
                  Color.lerp(base, Colors.black, 0.12)!,
                ],
              ),
              border: Border.all(
                color: Color.lerp(base, Colors.black, 0.28)!,
                width: sq * 0.045,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (base.toARGB32() == kDiamondBadgeColor.toARGB32())
                  _diamondPattern(sq),
                if (imageUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(radius * 0.7),
                    child: Image.network(
                      imageUrl!,
                      width: sq * 0.72,
                      height: sq * 0.72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _emoji(sq),
                    ),
                  )
                else
                  _emoji(sq),
              ],
            ),
          ),
          if (baremeLabel != null)
            Positioned(
              right: size * 0.02,
              bottom: size * 0.02,
              // Pastille de taille fixe, basée sur la taille NOMINALE du badge
              // (pas sur le carré, qui rétrécit quand il y a une étoile) : ainsi
              // toutes les pastilles sont identiques, avec ou sans étoile, quel
              // que soit le nombre de chiffres (le nombre rétrécit pour tenir).
              child: Container(
                width: size * 0.42,
                height: size * 0.30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1D40),
                  borderRadius: BorderRadius.circular(size * 0.11),
                  border: Border.all(
                    color: Color.lerp(base, Colors.white, 0.35)!,
                    width: size * 0.018,
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: size * 0.045),
                    child: Text(
                      baremeLabel!,
                      style: TextStyle(
                        fontSize: size * 0.24,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
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

  /// Petits 💎 parsemés sur le pourtour du carré (badges Diamant), autour de
  /// l'emoji central. Positions en fraction de la taille du carré.
  Widget _diamondPattern(double sq) {
    final d = sq * 0.16;
    const spots = <Offset>[
      Offset(0.07, 0.07),
      Offset(0.77, 0.07),
      Offset(0.07, 0.77),
      Offset(0.77, 0.77),
      Offset(0.42, 0.00),
      Offset(0.42, 0.84),
      Offset(0.00, 0.42),
      Offset(0.84, 0.42),
    ];
    return SizedBox(
      width: sq,
      height: sq,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final s in spots)
            Positioned(
              left: s.dx * sq,
              top: s.dy * sq,
              child: Text(
                '💎',
                style: TextStyle(
                  fontSize: d,
                  height: 1,
                  shadows: const [
                    Shadow(color: Color(0x66000000), blurRadius: 1.5),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
