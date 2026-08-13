import 'package:as_grinta/core/utils/name_validation.dart';
import 'package:as_grinta/core/widgets/sticky_header_table.dart';
import 'package:as_grinta/features/badges/data/statistics_badge_emblems_provider.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Affiche le nom seul partout, sauf dans le module Statistiques (/stats) où
/// les badges arborés sont affichés à droite du nom.
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

    final inStatistics = GoRouterState.of(context).uri.path == '/stats';
    if (!inStatistics || profileId == null) return nameText;

    final asyncBadges = ref.watch(statisticsBadgeEmblemsProvider);
    final badges = asyncBadges.asData?.value[profileId] ??
        const <StatisticsBadgeEmblemData>[];
    if (badges.isEmpty) return nameText;

    final requested =
        badgeSize ?? (resolved.fontSize ?? grintaTableCellFontSize) * 1.35;
    final emblemSize = requested < 36 ? 36.0 : requested;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: nameText),
        for (final badge in badges.take(2)) ...[
          const SizedBox(width: 5),
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
    return SizedBox(
      width: size,
      height: size * 1.28,
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
          starsMultiplyBareme: isCareerBadgeCategory(badge.category),
          starOverflow: true,
          size: render,
        ),
      ),
    );
  }
}
