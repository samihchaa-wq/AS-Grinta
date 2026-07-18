export 'package:as_grinta/features/predictions/data/leaderboard_repository.dart';

import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/sticky_header_table.dart';
import 'package:as_grinta/features/badges/presentation/name_with_badges.dart';
import 'package:as_grinta/features/predictions/data/leaderboard_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SeasonRankingPanel extends ConsumerWidget {
  const SeasonRankingPanel({super.key, this.onRefresh});

  final Future<void> Function()? onRefresh;

  String _format(double value) {
    if ((value - value.round()).abs() < 0.000001) return '${value.round()}';
    return '${value.ceil()}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaderboardAsync = ref.watch(leaderboardProvider);
    return leaderboardAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(humanizeError(error)),
        ),
      ),
      data: (entries) {
        final sorted = [...entries]..sort((a, b) {
            final points = b.seasonPoints.compareTo(a.seasonPoints);
            return points != 0 ? points : a.name.compareTo(b.name);
          });
        if (sorted.isEmpty ||
            sorted.every((entry) => entry.seasonPoints == 0)) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('Aucun point calculable pour le moment.'),
            ),
          );
        }

        return StickyHeaderTableCard(
          onRefresh: onRefresh,
          header: const _SeasonRankingHeader(),
          rows: [
            for (var index = 0; index < sorted.length; index++)
              _SeasonRankingRow(
                rank: index + 1,
                entry: sorted[index],
                points: _format(sorted[index].seasonPoints),
              ),
          ],
        );
      },
    );
  }
}

class _SeasonRankingHeader extends StatelessWidget {
  const _SeasonRankingHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 6, child: Text('Joueurs', style: style)),
          Expanded(
            flex: 2,
            child: Text(
              'Plus proches',
              style: style,
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text('Exacts', style: style, textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 2,
            child: Text('Points', style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _SeasonRankingRow extends StatelessWidget {
  const _SeasonRankingRow({
    required this.rank,
    required this.entry,
    required this.points,
  });

  final int rank;
  final LeaderboardEntry entry;
  final String points;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          Expanded(
            flex: 6,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    '$rank',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: NameWithBadges(
                    profileId: entry.profileId,
                    name: entry.name,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${entry.seasonBons}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${entry.seasonExacts}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              points,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
