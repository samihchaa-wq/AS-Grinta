import 'package:as_grinta/features/badges/presentation/badge_descriptor.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem_body.dart';
import 'package:flutter/material.dart';

export 'package:as_grinta/features/badges/presentation/badge_descriptor.dart';

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

String? baremeLabelFor(String? metric, int? value) {
  if (metric == null || value == null) return null;
  if (metric == 'max_match_goals' ||
      metric == 'seasons_complete' ||
      metric == 'bet_against_grinta' ||
      metric.startsWith('title_')) {
    return null;
  }
  return '$value';
}

/// Emblème d'un badge : un rectangle unique empilant l'illustration, la valeur
/// atteinte, le critère mesuré et sa temporalité.
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
  });

  final String emoji;
  final double size;
  final String? imageUrl;
  final String? color;
  final String? baremeLabel;

  /// Le socle. À défaut, une mention générique déduite de la nature du badge.
  final BadgeDescriptor? descriptor;

  final bool showStar;
  final int starCount;

  BadgeDescriptor get _descriptor {
    final given = descriptor;
    if (given != null) return given;
    if (showStar) return const BadgeDescriptor('PALMARÈS');
    if (baremeLabel != null) return const BadgeDescriptor('PERFORMANCE');
    return const BadgeDescriptor('EXPLOIT');
  }

  @override
  Widget build(BuildContext context) {
    final base = parseBadgeColor(color) ?? kDefaultBadgeColor;
    final fallback = Text(emoji, style: TextStyle(fontSize: size * 0.49));
    final illustration = imageUrl == null
        ? fallback
        : Image.network(
            imageUrl!,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => fallback,
          );

    return BadgeEmblemBody(
      size: size,
      base: base,
      descriptor: _descriptor,
      value: baremeLabel,
      child: showStar
          ? _Starred(size: size, count: starCount, child: illustration)
          : illustration,
    );
  }
}

/// Les étoiles de palmarès, posées dans l'illustration plutôt qu'au-dessus de
/// l'emblème : elles font partie de la pièce, elles ne la surmontent pas.
class _Starred extends StatelessWidget {
  const _Starred({
    required this.size,
    required this.count,
    required this.child,
  });

  final double size;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final stars = count < 1 ? 1 : count;
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Center(child: child),
        Padding(
          padding: EdgeInsets.only(top: size * 0.03),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < stars; i++)
                Icon(
                  Icons.star_rounded,
                  size: size * 0.18,
                  color: const Color(0xFFFCC21B),
                  shadows: [
                    Shadow(
                      color: const Color(0x8C000000),
                      blurRadius: size * 0.03,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
