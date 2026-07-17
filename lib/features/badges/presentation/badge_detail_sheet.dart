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
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BadgeDetailSheet(badge: badge, onAward: onAward),
  );
}

class BadgeDetailSheet extends ConsumerWidget {
  const BadgeDetailSheet({super.key, required this.badge, this.onAward});

  final BadgeDef badge;

  /// Si non nul, affiche un bouton « Attribuer / Retirer » (admin).
  final VoidCallback? onAward;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(badgeCatalogProvider).maybeWhen(
          data: (c) => c,
          orElse: () => const <BadgeDef>[],
        );

    // Tous les paliers de la même sous-famille, du plus petit au plus grand.
    final tiers = badge.metric == null
        ? <BadgeDef>[badge]
        : (catalog
            .where((b) => b.metric == badge.metric && b.kind == badge.kind)
            .toList()
          ..sort((a, b) => (a.threshold ?? 0).compareTo(b.threshold ?? 0)));
    final ladder = tiers.isEmpty ? <BadgeDef>[badge] : tiers;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BadgeEmblem(
                    emoji: badge.emoji,
                    imageUrl: badge.imageUrl,
                    color: badge.color,
                    baremeLabel: baremeLabelFor(badge.metric, badge.threshold),
                    showStar: badge.hasStar,
                    size: 78,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          badge.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (badge.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            badge.description,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (ladder.length > 1) ...[
                const SizedBox(height: 20),
                Text(
                  'Barème',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Chaque palier et ce qu’il récompense.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                for (final tier in ladder)
                  _TierRow(
                    tier: tier,
                    highlighted: tier.code == badge.code,
                  ),
              ],
              if (onAward != null) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onAward,
                    icon:
                        const Icon(Icons.workspace_premium_outlined, size: 18),
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: highlighted
            ? scheme.secondary.withValues(alpha: 0.12)
            : scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted ? scheme.secondary : scheme.outline,
          width: highlighted ? 2 : 1,
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
            size: 58,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tier.name,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (tier.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
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
