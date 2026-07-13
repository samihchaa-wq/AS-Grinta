import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/features/predictions/data/leaderboard_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SeasonRankingPanel extends ConsumerWidget {
  const SeasonRankingPanel({super.key});

  String _format(double value) {
    if ((value - value.round()).abs() < 0.000001) return '${value.round()}';
    return '${value.ceil()}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaderboardAsync = ref.watch(leaderboardProvider);
    return leaderboardAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(humanizeError(error)),
        ),
      ),
      data: (entries) {
        final sorted = [...entries]
          ..sort((a, b) {
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
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: sorted.indexed.map((indexed) {
              final rank = indexed.$1 + 1;
              final entry = indexed.$2;
              return Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    leading: CircleAvatar(
                      child: Text(
                        rank <= 3 ? ['🥇', '🥈', '🥉'][rank - 1] : '$rank',
                      ),
                    ),
                    title: Text(
                      entry.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _StatBadge(
                          label: 'Le plus proche',
                          value: entry.seasonBons,
                        ),
                        const SizedBox(width: 10),
                        _StatBadge(label: 'Exacts', value: entry.seasonExacts),
                        const SizedBox(width: 14),
                        Text(
                          '${_format(entry.seasonPoints)} pts',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                  if (rank < sorted.length) const Divider(height: 1),
                ],
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: scheme.primary,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
