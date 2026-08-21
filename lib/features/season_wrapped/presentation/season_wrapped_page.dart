import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bilan personnel de la saison qui vient de se terminer.
///
/// L'écran n'est atteignable que pendant l'intersaison. Les chiffres sont
/// figés au moment de la clôture : ils ne bougent plus.
class SeasonWrappedPage extends ConsumerWidget {
  const SeasonWrappedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wrapped = ref.watch(mySeasonWrappedProvider);

    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Ma saison')),
      body: wrapped.when(
        loading: () => const GrintaLoader.page(
          message: 'Préparation de ton bilan',
        ),
        error: (_, __) => const GrintaEmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Bilan indisponible',
          message: 'Ton bilan n’a pas pu être chargé. Réessaie plus tard.',
        ),
        data: (data) {
          if (data == null) {
            return const GrintaEmptyState(
              icon: Icons.emoji_events_outlined,
              title: 'Pas encore de bilan',
              message: 'Ton bilan apparaîtra à la fin de la saison.',
            );
          }
          return _WrappedBody(wrapped: data);
        },
      ),
    );
  }
}

class _WrappedBody extends StatelessWidget {
  const _WrappedBody({required this.wrapped});

  final SeasonWrapped wrapped;

  @override
  Widget build(BuildContext context) {
    final stats = wrapped.stats;

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      itemCount: stats.length + 1,
      separatorBuilder: (_, __) =>
          const SizedBox(height: AppSpacing.contentGap),
      itemBuilder: (context, index) {
        if (index == 0) return _WrappedHeader(wrapped: wrapped);
        return _StatCard(stat: stats[index - 1]);
      },
    );
  }
}

class _WrappedHeader extends StatelessWidget {
  const _WrappedHeader({required this.wrapped});

  final SeasonWrapped wrapped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Saison ${wrapped.seasonName}',
              style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.microGap),
          Text(
            'Ton bilan, figé à la clôture de la saison. '
            'Les classements portent sur les ${wrapped.rosterSize} joueurs '
            'ayant disputé au moins un match.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.stat});

  final SeasonWrappedStat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stat.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.microGap),
                  Text(stat.value, style: theme.textTheme.headlineSmall),
                  if (stat.note != null) ...[
                    const SizedBox(height: AppSpacing.microGap),
                    Text(
                      stat.note!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (stat.isRanked) _RankChip(rank: stat.rank!, pool: stat.pool!),
          ],
        ),
      ),
    );
  }
}

class _RankChip extends StatelessWidget {
  const _RankChip({required this.rank, required this.pool});

  final int rank;
  final int pool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPodium = rank <= 3;
    final background = isPodium
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final foreground = isPodium
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${frenchOrdinal(rank)} sur $pool',
        style: theme.textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// « 1er », puis « 2e », « 3e »…
String frenchOrdinal(int rank) => rank == 1 ? '1er' : '${rank}e';
