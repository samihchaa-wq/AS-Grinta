import 'package:as_grinta/features/badges/data/featured_badges_repository.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Affiche un prénom suivi des badges qu'il a choisi d'arborer (max 3),
/// à droite du nom. À utiliser partout où un nom de personne apparaît.
class NameWithBadges extends ConsumerWidget {
  const NameWithBadges({
    super.key,
    required this.profileId,
    required this.name,
    this.style,
    this.badgeSize = 30,
  });

  final String? profileId;
  final String name;
  final TextStyle? style;
  final double badgeSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameText = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    if (profileId == null) return nameText;

    final badges = ref.watch(featuredBadgesProvider).maybeWhen(
          data: (map) => map[profileId] ?? const <FeaturedBadge>[],
          orElse: () => const <FeaturedBadge>[],
        );
    if (badges.isEmpty) return nameText;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: nameText),
        for (final b in badges.take(2)) ...[
          const SizedBox(width: 4),
          _BadgeChip(badge: b, size: badgeSize),
        ],
      ],
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.badge, required this.size});
  final FeaturedBadge badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    return BadgeEmblem(
      emoji: badge.emoji,
      imageUrl: badge.imageUrl,
      color: badge.color,
      baremeLabel: badge.baremeLabel,
      size: size,
    );
  }
}
