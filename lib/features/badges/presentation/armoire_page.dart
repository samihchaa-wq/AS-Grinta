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
    // La gestion du palmarès est réservée aux administrateurs du club.
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
                  title: 'Validés',
                  count: armoire.validated.length,
                ),
                const SizedBox(height: 10),
                _BadgeGrid(
                  items: armoire.validated,
                  featured: featured,
                  onToggleFeatured: (code, value) =>
                      _toggleFeatured(context, ref, code, value),
                ),
                const SizedBox(height: 24),
              ],
              if (armoire.inProgress.isNotEmpty) ...[
                _SectionTitle(
                  title: 'En cours',
                  count: armoire.inProgress.length,
                ),
                const SizedBox(height: 10),
                _BadgeGrid(
                  items: armoire.inProgress,
                  featured: featured,
                  onToggleFeatured: (code, value) =>
                      _toggleFeatured(context, ref, code, value),
                ),
                const SizedBox(height: 24),
              ],
              if (armoire.locked.isNotEmpty) ...[
                _SectionTitle(
                  title: 'À débloquer',
                  count: armoire.locked.length,
                ),
                const SizedBox(height: 10),
                _BadgeGrid(
                  items: armoire.locked,
                  featured: featured,
                  onToggleFeatured: (code, value) =>
                      _toggleFeatured(context, ref, code, value),
                ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(
              Icons.emoji_events_rounded,
              color: AppTheme.reward,
              size: 34,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$validated badge${validated > 1 ? 's' : ''} débloqué${validated > 1 ? 's' : ''}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  if (inProgress > 0)
                    Text(
                      '$inProgress en cours',
                      style: const TextStyle(color: AppTheme.textFaint),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
        Chip(
          visualDensity: VisualDensity.compact,
          label: Text('$count'),
        ),
      ],
    );
  }
}

class _BadgeGrid extends StatelessWidget {
  const _BadgeGrid({
    required this.items,
    required this.featured,
    required this.onToggleFeatured,
  });

  final List<ArmoireBadge> items;
  final Set<String> featured;
  final Future<void> Function(String code, bool nowFeatured) onToggleFeatured;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 5
            : constraints.maxWidth >= 620
                ? 4
                : 3;
        final spacing = columns == 3 ? 10.0 : 14.0;
        final tileWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: tileWidth,
                child: _BadgeTile(
                  item: item,
                  featured: featured.contains(item.code),
                  onToggleFeatured: onToggleFeatured,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({
    required this.item,
    required this.featured,
    required this.onToggleFeatured,
  });

  final ArmoireBadge item;
  final bool featured;
  final Future<void> Function(String code, bool nowFeatured) onToggleFeatured;

  @override
  Widget build(BuildContext context) {
    final unlocked = item.unlocked;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => showBadgeDetailSheet(
        context,
        item: item,
        featured: featured,
        onToggleFeatured: unlocked
            ? (value) => onToggleFeatured(item.code, value)
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                BadgeEmblem(
                  imageUrl: item.imageUrl,
                  emoji: item.emoji,
                  colorHex: item.color,
                  hasStar: item.hasStar,
                  unlocked: unlocked,
                  size: 72,
                ),
                if (featured)
                  const Positioned(
                    right: -4,
                    top: -4,
                    child: Icon(
                      Icons.push_pin_rounded,
                      size: 18,
                      color: AppTheme.reward,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: unlocked
                        ? AppTheme.textPrimary
                        : AppTheme.textFaint,
                  ),
            ),
            if (!unlocked && item.progress != null) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: item.progress!.clamp(0, 1),
                minHeight: 4,
                borderRadius: BorderRadius.circular(99),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
