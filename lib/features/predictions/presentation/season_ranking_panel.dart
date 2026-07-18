export 'package:as_grinta/features/predictions/data/leaderboard_repository.dart';

import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/sticky_header_table.dart';
import 'package:as_grinta/features/badges/presentation/name_with_badges.dart';
import 'package:as_grinta/features/predictions/data/leaderboard_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _SrCol { name, closest, exact, points }

class SeasonRankingPanel extends ConsumerStatefulWidget {
  const SeasonRankingPanel({super.key, this.onRefresh});

  final Future<void> Function()? onRefresh;

  @override
  ConsumerState<SeasonRankingPanel> createState() => _SeasonRankingPanelState();
}

class _SeasonRankingPanelState extends ConsumerState<SeasonRankingPanel> {
  _SrCol _sort = _SrCol.points;
  bool _desc = true;

  String _format(double value) {
    if ((value - value.round()).abs() < 0.000001) return '${value.round()}';
    return '${value.ceil()}';
  }

  void _onSort(_SrCol col) {
    setState(() {
      if (_sort == col) {
        _desc = !_desc;
      } else {
        _sort = col;
        _desc = col != _SrCol.name;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
        if (entries.isEmpty ||
            entries.every((entry) => entry.seasonPoints == 0)) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('Aucun point calculable pour le moment.'),
            ),
          );
        }

        final sorted = [...entries]..sort((a, b) {
            int cmp;
            switch (_sort) {
              case _SrCol.name:
                cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
              case _SrCol.closest:
                cmp = a.seasonBons.compareTo(b.seasonBons);
              case _SrCol.exact:
                cmp = a.seasonExacts.compareTo(b.seasonExacts);
              case _SrCol.points:
                cmp = a.seasonPoints.compareTo(b.seasonPoints);
            }
            if (cmp == 0) cmp = a.seasonPoints.compareTo(b.seasonPoints);
            if (cmp == 0) {
              cmp = b.name.toLowerCase().compareTo(a.name.toLowerCase());
            }
            return _desc ? -cmp : cmp;
          });

        return StickyHeaderTableCard(
          onRefresh: widget.onRefresh,
          header: _header(context),
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

  Widget _header(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
      child: Row(
        children: [
          SortableHeaderCell(
            label: 'Joueurs',
            flex: 6,
            align: TextAlign.start,
            active: _sort == _SrCol.name,
            descending: _desc,
            onTap: () => _onSort(_SrCol.name),
            style: style,
          ),
          SortableHeaderCell(
            label: 'Plus proches',
            flex: 2,
            active: _sort == _SrCol.closest,
            descending: _desc,
            onTap: () => _onSort(_SrCol.closest),
            style: style,
          ),
          SortableHeaderCell(
            label: 'Exacts',
            flex: 2,
            active: _sort == _SrCol.exact,
            descending: _desc,
            onTap: () => _onSort(_SrCol.exact),
            style: style,
          ),
          SortableHeaderCell(
            label: 'Points',
            flex: 2,
            align: TextAlign.end,
            active: _sort == _SrCol.points,
            descending: _desc,
            onTap: () => _onSort(_SrCol.points),
            style: style,
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
      padding: const EdgeInsets.fromLTRB(8, 15, 12, 15),
      child: Row(
        children: [
          Expanded(
            flex: 6,
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: Text(
                    '$rank',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: NameWithBadges(
                    profileId: entry.profileId,
                    name: entry.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
