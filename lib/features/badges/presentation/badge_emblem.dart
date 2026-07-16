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

/// Emblème d'un badge : carré aux bords arrondis, coloré, avec l'emoji (ou une
/// image) dedans et, pour les paliers, le seuil écrit en petit dans un coin.
class BadgeEmblem extends StatelessWidget {
  const BadgeEmblem({
    super.key,
    required this.emoji,
    required this.size,
    this.imageUrl,
    this.color,
    this.baremeLabel,
  });

  final String emoji;
  final double size;
  final String? imageUrl;
  final String? color;
  final String? baremeLabel;

  @override
  Widget build(BuildContext context) {
    final base = parseBadgeColor(color) ?? kDefaultBadgeColor;
    final radius = size * 0.26;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
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
                width: size * 0.045,
              ),
            ),
            child: imageUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(radius * 0.7),
                    child: Image.network(
                      imageUrl!,
                      width: size * 0.72,
                      height: size * 0.72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Text(emoji, style: TextStyle(fontSize: size * 0.55)),
                    ),
                  )
                : Text(emoji, style: TextStyle(fontSize: size * 0.55)),
          ),
          if (baremeLabel != null)
            Positioned(
              right: size * 0.02,
              bottom: size * 0.02,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: size * 0.11,
                  vertical: size * 0.02,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1D40),
                  borderRadius: BorderRadius.circular(size * 0.16),
                  border: Border.all(
                    color: Color.lerp(base, Colors.white, 0.35)!,
                    width: size * 0.02,
                  ),
                ),
                child: Text(
                  baremeLabel!,
                  style: TextStyle(
                    fontSize: size * 0.3,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
