import 'package:as_grinta/core/utils/name_validation.dart';
import 'package:as_grinta/core/widgets/sticky_header_table.dart';
import 'package:as_grinta/features/badges/data/statistics_badge_emblems_provider.dart';
import 'package:as_grinta/features/badges/presentation/badge_display_scope.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const nameWithBadgesGap = 3.0;
const nameWithBadgesMinimumSize = 36.0;

/// Affiche le nom seul partout, sauf sous une [BadgeDisplayScope] active — le
/// module Statistiques — où les badges arborés sont affichés à droite du nom.
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
  final TextStyle? style;
  final double? badgeSize;

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
    final nameText = Text(
      capitalizePersonName(name),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: resolved,
    );

    if (!BadgeDisplayScope.of(context) || profileId == null) return nameText;

    final asyncBadges = ref.watch(statisticsBadgeEmblemsProvider);
    final badges = asyncBadges.asData?.value[profileId] ??
        const <StatisticsBadgeEmblemData>[];
    if (badges.isEmpty) return nameText;

    final requested =
        badgeSize ?? (resolved.fontSize ?? grintaTableCellFontSize) * 1.35;
    final emblemSize = requested < nameWithBadgesMinimumSize
        ? nameWithBadgesMinimumSize
        : requested;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: nameText),
        for (final badge in badges.take(1)) ...[
          const SizedBox(width: nameWithBadgesGap),
          _BadgeChip(badge: badge, size: emblemSize),
        ],
      ],
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.badge, required this.size});

  final StatisticsBadgeEmblemData badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    const render = 96.0;
    // La hauteur réservée colle exactement à celle de l'emblème : aucune bande
    // vide au-dessus ou en dessous ne vient rogner sa taille dans la ligne.
    final ratio = badgeEmblemHeightRatio(
      hasValue: badge.valueLabel?.isNotEmpty == true,
      hasPeriod: badge.descriptor.period != null,
      hasStar: badge.hasStar,
    );
    return SizedBox(
      width: size,
      height: size * ratio,
      child: FittedBox(
        fit: BoxFit.contain,
        clipBehavior: Clip.none,
        child: BadgeEmblem(
          emoji: badge.emoji,
          imageUrl: badge.imageUrl,
          color: badge.color,
          baremeLabel: badge.valueLabel,
          descriptor: badge.descriptor,
          showStar: badge.hasStar,
          starCount: badge.stars,
          size: render,
        ),
      ),
    );
  }
}
