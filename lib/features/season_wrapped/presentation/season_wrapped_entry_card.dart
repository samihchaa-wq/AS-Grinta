import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Entrée vers le bilan de saison, visible uniquement entre deux saisons.
///
/// La carte disparaît d'elle-même dès qu'une nouvelle saison est créée : la
/// base cesse alors de servir le bilan.
class SeasonWrappedEntryCard extends ConsumerWidget {
  const SeasonWrappedEntryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(seasonWrappedStateProvider);
    final available = state.valueOrNull?.available ?? false;
    if (!available) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final seasonName = state.valueOrNull?.seasonName;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.contentGap,
        AppSpacing.screenGutter,
        AppSpacing.contentGap,
      ),
      child: Card(
        margin: EdgeInsets.zero,
        color: theme.colorScheme.primaryContainer,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push('/wrapped'),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: AppSpacing.cardPadding),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ma saison',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        seasonName == null
                            ? 'Ton bilan personnel est prêt.'
                            : 'Ton bilan personnel de la saison $seasonName '
                                'est prêt.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
