import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/badges/data/badge_repository.dart';
import 'package:as_grinta/features/badges/data/featured_badges_repository.dart';
import 'package:as_grinta/features/badges/presentation/badge_detail_sheet.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Armoire à badges : Validés · En cours · À débloquer.
class ArmoirePage extends ConsumerWidget {
  const ArmoirePage({super.key});

  Future<void> _toggleFeatured(
    BuildContext context,
    WidgetRef ref,
    String code,
    bool nowFeatured,
  ) async {
    try {
      await ref
          .read(featuredBadgesRepositoryProvider)
          .setFeatured(code, nowFeatured);
      ref.invalidate(myFeaturedCodesProvider);
      ref.invalidate(featuredBadgesProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(humanizeError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final armoireAsync = ref.watch(myArmoireProvider);
    final featured = ref
        .watch(myFeaturedCodesProvider)
        .maybeWhen(data: (codes) => codes, orElse: () => const <String>{});
    final isAdmin = ref.watch(isAdminViewProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Armoire à badges'),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'Gérer les badges',
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => context.push('/admin/badges'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myArmoireProvider);
          ref.invalidate(myFeaturedCodesProvider);
          await ref.read(myArmoireProvider.future);
        },
        child: armoireAsync.when(
          loading: () => const Center(child: GrintaProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: GrintaEmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Collection indisponible',
                  message: humanizeError(e),
                ),
              ),
            ],
          ),
          data: (armoire) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              _Header(
                validated: armoire.validated.length,
                inProgress: armoire.inProgress.length,
              ),
              const SizedBox(height: 24),
              if (armoire.validated.isEmpty &&
                  armoire.inProgress.isEmpty &&
                  armoire.locked.isEmpty)
                const Card(
                  child: GrintaEmptyState(
                    icon: Icons.emoji_events_outlined,
                    title: 'Ta collection est vide',
                    message: 'Joue, pronostique et gagne des matchs pour '
                        'débloquer tes premiers badges.',
                  ),
                ),
              if (armoire.validated.isNotEmpty) ...[
                _SectionTitle(
                  title: 'Débloqués',
                  count: armoire.validated.length,
                  icon: Icons.workspace_premium_rounded,
                ),
                const SizedBox(height: 6),
                Text(
                  'Sélectionne jusqu’à 2 badges à afficher près de ton prénom.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppTheme.textFaint),
                ),
                const SizedBox(height: 14),
                _BadgeGrid(
                  badges: armoire.validated,
                  featuredCodes: featured,
                  onToggleFeatured: (code, nowFeatured) =>
                      _toggleFeatured(context, ref, code, nowFeatured),
                ),
                const SizedBox(height: 28),
              ],
              if (armoire.inProgress.isNotEmpty) ...[
                _SectionTitle(
                  title: 'En progression',
                  count: armoire.inProgress.length,
                  icon: Icons.trending_up_rounded,
                ),
                const SizedBox(height: 14),
                ...armoire.inProgress.map((b) => _InProgressTile(badge: b)),
                const SizedBox(height: 20),
              ],
              if (armoire.locked.isNotEmpty) ...[
                _SectionTitle(
                  title: 'À découvrir',
                  count: armoire.locked.length,
                  icon: Icons.lock_outline_rounded,
                ),
                const SizedBox(height: 6),
                Text(
                  'Continue à jouer pour révéler ces récompenses.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppTheme.textFaint),
                ),
                const SizedBox(height: 14),
                _BadgeGrid(badges: armoire.locked, locked: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.validated, required this.inProgress});

  final int validated;
  final int inProgress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.outline.withValues(alpha: .56)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.reward.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: AppTheme.reward.withValues(alpha: .34)),
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: AppTheme.reward,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ma collection',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '$validated débloqué${validated > 1 ? 's' : ''} · '
                  '$inProgress en progression',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppTheme.textFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.count,
    required this.icon,
  });

  final String title;
  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primaryBright),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppTheme.surfaceHigh,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppTheme.outline.withValues(alpha: .46)),
          ),
          child: Text(
            '$count',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textSecondary,
                ),
          ),
        ),
      ],
    );
  }
}

class _BadgeGrid extends StatelessWidget {
  const _BadgeGrid({
    required this.badges,
    this.locked = false,
    this.featuredCodes,
    this.onToggleFeatured,
  });

  final List<ArmoireBadge> badges;
  final bool locked;
  final Set<String>? featuredCodes;
  final void Function(String code, bool nowFeatured)? onToggleFeatured;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 16,
      children: [
        for (final b in badges)
          _BadgeTile(
            badge: b,
            locked: locked,
            featured: featuredCodes?.contains(b.def.code) ?? false,
            onToggleFeatured: onToggleFeatured,
          ),
      ],
    );
  }
}

String? baremeThreshold(BadgeDef def) =>
    baremeLabelFor(def.metric, def.threshold);

class _BadgeTile extends ConsumerWidget {
  const _BadgeTile({
    required this.badge,
    this.locked = false,
    this.featured = false,
    this.onToggleFeatured,
  });

  final ArmoireBadge badge;
  final bool locked;
  final bool featured;
  final void Function(String code, bool nowFeatured)? onToggleFeatured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const columns = 4;
    final tile =
        (MediaQuery.of(context).size.width - 32 - (columns - 1) * 12) / columns;
    final emblem = tile < 58 ? tile : 58.0;

    if (locked) {
      return SizedBox(
        width: tile,
        child: Column(
          children: [
            Container(
              height: emblem,
              width: emblem,
              decoration: BoxDecoration(
                color: AppTheme.surfaceHigh.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(emblem * .24),
                border: Border.all(
                  color: AppTheme.outline.withValues(alpha: .38),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.lock_outline_rounded,
                color: AppTheme.textFaint.withValues(alpha: .55),
                size: 22,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'Mystère',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.textFaint.withValues(alpha: .72),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      );
    }

    final canFeature = onToggleFeatured != null;
    final bareme = baremeThreshold(badge.def);
    return SizedBox(
      width: tile,
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              if (badge.isNew) {
                final uid =
                    ref.read(supabaseClientProvider).auth.currentUser?.id;
                if (uid != null) {
                  ref
                      .read(badgeRepositoryProvider)
                      .markBadgeSeen(uid, badge.def.code);
                  ref.invalidate(myArmoireProvider);
                }
              }
              showBadgeDetailSheet(
                context,
                badge.def,
                isFeatured: featured,
                onToggleFeatured: canFeature
                    ? () => onToggleFeatured!(badge.def.code, !featured)
                    : null,
              );
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                BadgeEmblem(
                  emoji: badge.def.emoji,
                  imageUrl: badge.def.imageUrl,
                  color: badge.def.color,
                  baremeLabel: bareme,
                  showStar: badge.def.hasStar,
                  starCount: badge.stars,
                  starsMultiplyBareme: isCareerBadgeCategory(
                    badge.def.category,
                  ),
                  size: emblem,
                ),
                if (badge.isNew)
                  Positioned(
                    top: -2,
                    left: -2,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: AppTheme.accent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.background,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                if (featured)
                  Positioned(
                    top: -3,
                    right: -3,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: AppTheme.reward,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.background,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.star_rounded,
                        size: 12,
                        color: AppTheme.background,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Text(
            badge.def.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
          ),
        ],
      ),
    );
  }
}

class _InProgressTile extends StatelessWidget {
  const _InProgressTile({required this.badge});

  final ArmoireBadge badge;

  @override
  Widget build(BuildContext context) {
    final showProgress = badge.target != null;
    return GestureDetector(
      onTap: () => showBadgeDetailSheet(context, badge.def),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: AppTheme.outline.withValues(alpha: .52)),
        ),
        child: Row(
          children: [
            BadgeEmblem(
              emoji: badge.def.emoji,
              imageUrl: badge.def.imageUrl,
              color: badge.def.color,
              baremeLabel: baremeThreshold(badge.def),
              showStar: badge.def.hasStar,
              starCount: badge.stars,
              starsMultiplyBareme: isCareerBadgeCategory(badge.def.category),
              size: 54,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    badge.def.name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  if (badge.def.description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      badge.def.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textFaint,
                          ),
                    ),
                  ],
                  if (showProgress) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: GrintaLinearProgressIndicator(
                              value: badge.progress ?? 0,
                              minHeight: 6,
                              backgroundColor: AppTheme.surfaceHigh,
                              valueColor: const AlwaysStoppedAnimation(
                                AppTheme.primaryBright,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${badge.current}/${badge.target}',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.textFaint),
          ],
        ),
      ),
    );
  }
}
