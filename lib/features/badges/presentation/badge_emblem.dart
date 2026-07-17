import 'package:flutter/material.dart';

/// Couleur par défaut d'un emblème quand aucune n'est définie.
const Color kDefaultBadgeColor = Color(0xFF3A4568);

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

    // Réserve le haut de la boîte pour l'étoile, le carré occupe le bas :
    // l'encombrement reste `size` × `size` partout (pas de débordement).
    final squareSize = size * 0.76;
    final starSize = size * 0.34;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          _square(base, squareSize),
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
            child: imageUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(radius * 0.7),
                    child: Image.network(
                      imageUrl!,
                      width: sq * 0.72,
                      height: sq * 0.72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _emoji(sq),
                    ),
                  )
                : _emoji(sq),
          ),
          if (baremeLabel != null)
            Positioned(
              right: sq * 0.02,
              bottom: sq * 0.02,
              // Pastille de taille fixe : le nombre rétrécit pour tenir, donc
              // toutes les pastilles ont la même taille (1, 2 ou 3 chiffres).
              child: Container(
                width: sq * 0.46,
                height: sq * 0.32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1D40),
                  borderRadius: BorderRadius.circular(sq * 0.12),
                  border: Border.all(
                    color: Color.lerp(base, Colors.white, 0.35)!,
                    width: sq * 0.02,
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: sq * 0.05),
                    child: Text(
                      baremeLabel!,
                      style: TextStyle(
                        fontSize: sq * 0.26,
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
}
