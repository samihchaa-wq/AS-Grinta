import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/badges/data/badge_repository.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ouvre la feuille de détail d'un badge : sa description, tout son barème
/// (chaque palier + sa description) et, pour l'admin, un bouton d'attribution.
void showBadgeDetailSheet(
  BuildContext context,
  BadgeDef badge, {
  VoidCallback? onAward,
  bool isFeatured = false,
  VoidCallback? onToggleFeatured,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppTheme.surface,
    barrierColor: Colors.black.withValues(alpha: .62),
    builder: (_) => BadgeDetailSheet(
      badge: badge,
      onAward: onAward,
      isFeatured: isFeatured,
      onToggleFeatured: onToggleFeatured,
    ),
  );
}

class BadgeDetailSheet extends ConsumerWidget {
  const BadgeDetailSheet({
    super.key,
    required this.badge,
    this.onAward,
    this.isFeatured = false,
    this.onToggleFeatured,
  });

  final BadgeDef badge;
  final VoidCallback? onAward;
  final bool isFeatured;
  final VoidCallback? onToggleFeatured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref
        .watch(badgeCatalogProvider)
        .maybeWhen(data: (c) => c, orElse: () => const <BadgeDef>[]);

    final tiers = (badge.metric == null || badge.standalone)
        ? <BadgeDef>[badge]
        : (catalog
            .where(
              (b) =>
                  b.metric == badge.metric &&
                  b.kind == badge.kind &&
                  !b.standalone,
            )
            .toList()
          ..sort((a, b) => (a.threshold ?? 0).compareTo(b.threshold ?? 0)));
    final ladder = tiers.isEmpty ? <BadgeDef>[badge] : tiers;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.surfaceHero.withValues(alpha: .94),
                      AppTheme.surfaceHigh.withValues(alpha: .84),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  border: Border.all(
                    color: AppTheme.reward.withValues(alpha: .22),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    BadgeEmblem(
                      emoji: badge.emoji,
                      imageUrl: badge.imageUrl,
                      color: badge.color,
                      baremeLabel: baremeLabelFor(
                        badge.metric,
                        badge.threshold,
                      ),
                      showStar: badge.hasStar,
                      size: 82,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            badge.name,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          if (badge.description.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              badge.description,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: AppTheme.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (ladder.length > 1) ...[
                const SizedBox(height: 24),
                Text(
                  'BARÈME',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppTheme.textSecondary,
                        letterSpacing: .8,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Chaque palier et ce qu’il récompense.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                for (final tier in ladder)
                  _TierRow(tier: tier, highlighted: tier.code == badge.code),
              ],
              if (onToggleFeatured != null) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: isFeatured
                      ? OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            onToggleFeatured!();
                          },
                          icon: const Icon(Icons.star_border_rounded, size: 18),
                          label: const Text('Ne plus arborer'),
                        )
                      : FilledButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            onToggleFeatured!();
                          },
                          icon: const Icon(Icons.star_rounded, size: 18),
                          label: const Text('Arborer ce badge'),
                        ),
                ),
              ],
              if (onAward != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onAward,
                    icon: const Icon(
                      Icons.workspace_premium_outlined,
                      size: 18,
                    ),
                    label: const Text('Attribuer / Retirer ce badge'),
                  ),
                ),
              ],
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _TierRow extends StatelessWidget {
  const _TierRow({required this.tier, required this.highlighted});

  final BadgeDef tier;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlighted
            ? AppTheme.reward.withValues(alpha: .10)
            : AppTheme.surfaceHigh.withValues(alpha: .46),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: highlighted
              ? AppTheme.reward.withValues(alpha: .46)
              : AppTheme.outline.withValues(alpha: .28),
          width: highlighted ? 1.4 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          BadgeEmblem(
            emoji: tier.emoji,
            imageUrl: tier.imageUrl,
            color: tier.color,
            baremeLabel: baremeLabelFor(tier.metric, tier.threshold),
            showStar: tier.hasStar,
            size: 56,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tier.name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: highlighted
                            ? AppTheme.reward
                            : AppTheme.textPrimary,
                      ),
                ),
                if (tier.description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    tier.description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
