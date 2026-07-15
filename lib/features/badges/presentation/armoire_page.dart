import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/features/badges/data/badge_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Armoire à badges : Validés · En cours · À débloquer.
class ArmoirePage extends ConsumerWidget {
  const ArmoirePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final armoireAsync = ref.watch(myArmoireProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Armoire à badges')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myArmoireProvider);
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
              _Header(
                validated: armoire.validated.length,
                total: armoire.validated.length +
                    armoire.inProgress.length +
                    armoire.locked.length,
              ),
              const SizedBox(height: 20),
              if (armoire.validated.isNotEmpty) ...[
                _SectionTitle('Validés', armoire.validated.length),
                const SizedBox(height: 10),
                _BadgeGrid(badges: armoire.validated),
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
  const _Header({required this.validated, required this.total});
  final int validated;
  final int total;

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ma collection',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w800)),
                Text('$validated badge${validated > 1 ? 's' : ''} obtenu${validated > 1 ? 's' : ''} sur $total',
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

class _BadgeGrid extends StatelessWidget {
  const _BadgeGrid({required this.badges, this.locked = false});
  final List<ArmoireBadge> badges;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [for (final b in badges) _BadgeTile(badge: b, locked: locked)],
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge, this.locked = false});
  final ArmoireBadge badge;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = (MediaQuery.of(context).size.width - 32 - 24) / 3;

    if (locked) {
      return SizedBox(
        width: width,
        child: Column(
          children: [
            Container(
              height: width,
              decoration: BoxDecoration(
                color: const Color(0xFF0A1428),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF1B2A48)),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.lock_outline,
                  color: Color(0xFF3B4A6B), size: 30),
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

    return SizedBox(
      width: width,
      child: Column(
        children: [
          Container(
            height: width,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.secondary.withValues(alpha: 0.22),
                  scheme.surfaceContainerHighest,
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: scheme.secondary.withValues(alpha: 0.5)),
            ),
            alignment: Alignment.center,
            child: badge.def.imageUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(badge.def.imageUrl!,
                        width: width * 0.6, height: width * 0.6, fit: BoxFit.cover),
                  )
                : Text(badge.def.emoji, style: const TextStyle(fontSize: 34)),
          ),
          const SizedBox(height: 6),
          Text(
            badge.seasonsWon > 1
                ? '${badge.def.name} ×${badge.seasonsWon}'
                : badge.def.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontWeight: FontWeight.w700),
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
    final remaining = badge.remaining ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outline),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: 0.55,
            child: Text(badge.def.emoji, style: const TextStyle(fontSize: 28)),
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
                  '${badge.current}/${badge.target} · plus que $remaining',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
