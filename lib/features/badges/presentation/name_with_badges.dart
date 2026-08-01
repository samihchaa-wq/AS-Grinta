import 'package:as_grinta/core/utils/name_validation.dart';
import 'package:as_grinta/core/widgets/sticky_header_table.dart';
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
    this.badgeSize,
  });

  final String? profileId;
  final String name;

  /// Fusionné par-dessus la référence : un écran qui ne précise que la couleur
  /// ou la graisse garde donc la taille commune. Seul un `fontSize` explicite
  /// s'en écarte.
  final TextStyle? style;

  /// Déduit de la taille du nom quand il n'est pas donné, pour que le badge
  /// suive toujours le texte qu'il accompagne.
  final double? badgeSize;

  /// Taille de référence d'un nom de joueur dans une liste. Elle vient des
  /// classements ; tous les autres écrans s'alignent dessus pour qu'un même
  /// joueur ait partout la même stature.
  TextStyle _resolvedStyle(BuildContext context) {
    final base = grintaTableCellTextStyle(
      context,
      fontWeight: FontWeight.w800,
    );
    return style == null ? base : base.merge(style);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = _resolvedStyle(context);
    final emblemSize =
        badgeSize ?? (resolved.fontSize ?? grintaTableCellFontSize) * 1.35;
    final nameText = Text(
      capitalizePersonName(name),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: resolved,
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
          _BadgeChip(badge: b, size: emblemSize),
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
    // On dessine l'emblème à haute résolution puis on le réduit : sur le web,
    // un emoji rendu directement à petite taille sort délavé et sans détail.
    // Le supersampling garantit le même dessin net que dans l'armoire.
    const render = 96.0;
    // L'empreinte du badge = le carré (size×size), aligné verticalement avec le
    // nom. L'étoile déborde au-dessus sans décaler le carré, et les deux badges
    // côte à côte restent alignés entre eux (leurs carrés) et avec le nom.
    return SizedBox(
      width: size,
      height: size,
      child: FittedBox(
        fit: BoxFit.contain,
        clipBehavior: Clip.none,
        child: BadgeEmblem(
          emoji: badge.emoji,
          imageUrl: badge.imageUrl,
          color: badge.color,
          baremeLabel: badge.baremeLabel,
          showStar: badge.hasStar,
          starCount: badge.stars,
          starsMultiplyBareme: isCareerBadgeCategory(badge.category),
          starOverflow: true,
          size: render,
        ),
      ),
    );
  }
}
