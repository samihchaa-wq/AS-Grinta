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

bool isCareerBadgeCategory(String? category) =>
    category == 'joueur_all_time' || category == 'pronos_all_time';

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
  final int starCount;
  final bool starsMultiplyBareme;
  final bool starOverflow;

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
    final footer = descriptor?.isNotEmpty == true
        ? descriptor!
        : showStar
            ? 'PALMARÈS'
            : baremeLabel != null
                ? 'PERFORMANCE'
                : 'EXPLOIT';
    final body = BadgeEmblemBody(
      child: illustration,
      size: size,
      base: base,
      footer: footer,
      value: baremeLabel,
    );
    if (!showStar) return body;
    final count = starCount < 1 ? 1 : starCount;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        body,
        Positioned(
          top: -size * 0.13,
          child: Row(
            children: [
              for (var i = 0; i < count; i++)
                Icon(
                  Icons.star_rounded,
                  size: size * 0.2,
                  color: const Color(0xFFFCC21B),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
