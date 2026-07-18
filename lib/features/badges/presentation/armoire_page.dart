import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(humanizeError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final armoireAsync = ref.watch(myArmoireProvider);
    final featured = ref.watch(myFeaturedCodesProvider).maybeWhen(
          data: (codes) => codes,
          orElse: () => const <String>{},
        );
    final isAdmin =
        ref.watch(authControllerProvider).profile?.role == AuthRole.admin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Armoire à badges'),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'Gérer les badges',
              icon: const Text('🏆', style: TextStyle(fontSize: 20)),
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
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [Text(humanizeError(e))],
          ),
          data: (armoire) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              const _Header(),
              const SizedBox(height: 20),
              if (armoire.validated.isNotEmpty) ...[
                _SectionTitle('Validés', armoire.validated.length),
                const SizedBox(height: 4),
                Text(
                  'Touche un badge pour l\'arborer à côté de ton prénom '
                  '(2 maximum).',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                _BadgeGrid(
                  badges: armoire.validated,
                  featuredCodes: featured,
                  onToggleFeatured: (code, nowFeatured) =>
                      _toggleFeatured(context, ref, code, nowFeatured),
                ),
                const SizedBox(height: 24),
              ],
              if (armoire.inProgress.isNotEmpty) ...[
                _SectionTitle('En cours', armoire.inProgress.length),
                const SizedBox(height: 10),
                ...armoire.inProgress.map((b) => _InProgressTile(badge: b)),
                const SizedBox(height: 24),
              ],
              if (armoire.locked.isNotEmpty) ...[
                _SectionTitle('À débloquer', armoire.locked.length),
                const SizedBox(height: 4),
                Text(
                  'Des badges mystères à découvrir…',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
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
  const _Header();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B3B6B), Color(0xFF0B1D40)],
        ),
        border: Border.all(color: scheme.secondary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Text('🏆', style: TextStyle(fontSize: 34)),
          const SizedBox(width: 14),
          Expanded(
            child: Text('Ma collection',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.count);
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('$count',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
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

  /// Codes des badges actuellement arborés (section « Validés » uniquement).
  final Set<String>? featuredCodes;
  final void Function(String code, bool nowFeatured)? onToggleFeatured;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
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

/// Le seuil à écrire en petit sur l'emblème d'un badge de barème.
String? baremeThreshold(BadgeDef def) =>
    baremeLabelFor(def.metric, def.threshold);

class _BadgeTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Emblème à la même taille que les badges « En cours » ; grille sur
    // 4 colonnes pour bien répartir les badges validés.
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
                color: const Color(0xFF0A1428),
                borderRadius: BorderRadius.circular(emblem * 0.26),
                border: Border.all(color: const Color(0xFF1B2A48)),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.lock_outline,
                  color: Color(0xFF3B4A6B), size: 24),
            ),
            const SizedBox(height: 6),
            Text('???',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: const Color(0xFF54617F))),
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
            onTap: () => showBadgeDetailSheet(
              context,
              badge.def,
              isFeatured: featured,
              onToggleFeatured: canFeature
                  ? () => onToggleFeatured!(badge.def.code, !featured)
                  : null,
            ),
            child: Stack(
              children: [
                BadgeEmblem(
                  emoji: badge.def.emoji,
                  imageUrl: badge.def.imageUrl,
                  color: badge.def.color,
                  baremeLabel: bareme,
                  showStar: badge.def.hasStar,
                  starCount: badge.stars,
                  size: emblem,
                ),
                if (featured)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(emblem * 0.26),
                        border: Border.all(color: scheme.secondary, width: 3),
                      ),
                    ),
                  ),
                if (featured)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: scheme.secondary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.star_rounded,
                          size: 15, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            badge.def.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: featured ? scheme.secondary : null,
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
    final scheme = Theme.of(context).colorScheme;
    // Barème à un seul palier (titres, exploits) : pas de progression.
    final showProgress = badge.target != null;
    return GestureDetector(
      onTap: () => showBadgeDetailSheet(context, badge.def),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outline),
        ),
        child: Row(
          children: [
            // Badge automatique : logo visible + progression (les joueurs
            // voient ce qu'ils peuvent débloquer).
            BadgeEmblem(
              emoji: badge.def.emoji,
              imageUrl: badge.def.imageUrl,
              color: badge.def.color,
              baremeLabel: baremeThreshold(badge.def),
              showStar: badge.def.hasStar,
              starCount: badge.stars,
              size: 58,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(badge.def.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  if (badge.def.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(badge.def.description,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                  if (showProgress) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: badge.progress ?? 0,
                        minHeight: 7,
                        backgroundColor: scheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation(scheme.secondary),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${badge.current}/${badge.target}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
