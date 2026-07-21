import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/sticky_header_table.dart';
import 'package:as_grinta/features/badges/presentation/name_with_badges.dart';
import 'package:as_grinta/features/statistics/data/statistics_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _StatisticsSection { players, team }

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  _StatisticsSection _section = _StatisticsSection.players;
  StatisticsPeriod _period = StatisticsPeriod.current;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GrintaAppBar(
        title: const Text('Statistiques'),
        actions: grintaHomeActions(context),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<_StatisticsSection>(
                expandedInsets: EdgeInsets.zero,
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: _StatisticsSection.players,
                    icon: Icon(Icons.groups_2_outlined),
                    label: Text('Joueurs'),
                  ),
                  ButtonSegment(
                    value: _StatisticsSection.team,
                    icon: Icon(Icons.shield_outlined),
                    label: Text('Équipe'),
                  ),
                ],
                selected: {_section},
                onSelectionChanged: (selection) {
                  setState(() => _section = selection.first);
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<StatisticsPeriod>(
                expandedInsets: EdgeInsets.zero,
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: StatisticsPeriod.current,
                    label: Text('Actuelle'),
                  ),
                  ButtonSegment(
                    value: StatisticsPeriod.previous,
                    label: Text('Précédente'),
                  ),
                  ButtonSegment(
                    value: StatisticsPeriod.allTime,
                    label: Text('Toutes'),
                  ),
                ],
                selected: {_period},
                onSelectionChanged: (selection) {
                  setState(() => _period = selection.first);
                },
              ),
            ),
          ),
          Expanded(
            child: switch (_section) {
              _StatisticsSection.players =>
                _PlayerStatisticsPeriodView(period: _period),
              _StatisticsSection.team =>
                _TeamStatisticsPeriodView(period: _period),
            },
          ),
        ],
      ),
    );
  }
}

class _PlayerStatisticsPeriodView extends ConsumerStatefulWidget {
  const _PlayerStatisticsPeriodView({required this.period});

  final StatisticsPeriod period;

  @override
  ConsumerState<_PlayerStatisticsPeriodView> createState() =>
      _PlayerStatisticsPeriodViewState();
}

class _PlayerStatisticsPeriodViewState
    extends ConsumerState<_PlayerStatisticsPeriodView> {
  // Colonne de tri active (null = ordre du classement fourni par le serveur).
  _StatCol? _sort;
  bool _desc = true;

  void _onSort(_StatCol col) {
    setState(() {
      if (_sort == col) {
        _desc = !_desc;
      } else {
        _sort = col;
        _desc =
            col != _StatCol.name; // noms A→Z, chiffres du + grand au + petit
      }
    });
  }

  num _value(_StatCol col, PlayerStatistics p) => switch (col) {
        _StatCol.played => p.matchesPlayed ?? 0,
        _StatCol.wins => p.wins ?? 0,
        _StatCol.draws => p.draws ?? 0,
        _StatCol.losses => p.losses ?? 0,
        _StatCol.main => p.isGoalkeeper ? p.cleanSheets : p.goals,
        _StatCol.hdm => p.hdm ?? 0,
        _StatCol.name => 0,
      };

  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch(statisticsPeriodProvider(widget.period));

    return dataAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ScrollableMessage(
        message: humanizeError(error),
        onRefresh: _refresh,
      ),
      data: (data) {
        if (data.players.isEmpty) {
          return _ScrollableMessage(
            message: 'Aucune statistique joueur disponible.',
            onRefresh: _refresh,
          );
        }
        final players = [...data.players];
        final sort = _sort;
        if (sort != null) {
          players.sort((a, b) {
            final cmp = sort == _StatCol.name
                ? a.playerName
                    .toLowerCase()
                    .compareTo(b.playerName.toLowerCase())
                : _value(sort, a).compareTo(_value(sort, b));
            return _desc ? -cmp : cmp;
          });
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: StickyHeaderTableCard(
            onRefresh: _refresh,
            header: _StatisticsHeaderRow(
              sort: _sort,
              descending: _desc,
              onSort: _onSort,
            ),
            rows: [
              for (var i = 0; i < players.length; i++)
                _StatisticsDataRow(rank: i + 1, player: players[i]),
            ],
          ),
        );
      },
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(statisticsPeriodProvider(widget.period));
    await ref.read(statisticsPeriodProvider(widget.period).future);
  }
}

class _TeamStatisticsPeriodView extends ConsumerWidget {
  const _TeamStatisticsPeriodView({required this.period});

  final StatisticsPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(teamStatisticsPeriodProvider(period));

    Future<void> refresh() async {
      ref.invalidate(teamStatisticsPeriodProvider(period));
      await ref.read(teamStatisticsPeriodProvider(period).future);
    }

    return dataAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ScrollableMessage(
        message: humanizeError(error),
        onRefresh: refresh,
      ),
      data: (statistics) => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _TeamSummaryCard(statistics: statistics),
            const SizedBox(height: 16),
            _TeamMetricGrid(statistics: statistics),
          ],
        ),
      ),
    );
  }
}

class _TeamSummaryCard extends StatelessWidget {
  const _TeamSummaryCard({required this.statistics});

  final TeamStatistics statistics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.shield_rounded,
                    color: colors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AS Grinta',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        statistics.periodLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${statistics.matchesPlayed}',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'match${statistics.matchesPlayed > 1 ? 's' : ''}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _RecordPill(
                  label: 'V',
                  value: statistics.wins,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                _RecordPill(
                  label: 'N',
                  value: statistics.draws,
                  color: colors.tertiary,
                ),
                const SizedBox(width: 8),
                _RecordPill(
                  label: 'D',
                  value: statistics.losses,
                  color: colors.error,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  'Taux de victoire',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  '${statistics.winRate.toStringAsFixed(1).replaceAll('.', ',')} %',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              minHeight: 8,
              borderRadius: BorderRadius.circular(99),
              value: statistics.winRate / 100,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordPill extends StatelessWidget {
  const _RecordPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
            const SizedBox(width: 7),
            Text(
              '$value',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamMetricGrid extends StatelessWidget {
  const _TeamMetricGrid({required this.statistics});

  final TeamStatistics statistics;

  String _average(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    final difference = statistics.goalDifference;
    final differenceLabel = difference > 0 ? '+$difference' : '$difference';
    final metrics = [
      _TeamMetric(
        label: 'Buts marqués',
        value: '${statistics.goalsFor}',
        icon: Icons.sports_soccer_rounded,
      ),
      _TeamMetric(
        label: 'Buts encaissés',
        value: '${statistics.goalsAgainst}',
        icon: Icons.gpp_bad_outlined,
      ),
      _TeamMetric(
        label: 'Différence',
        value: differenceLabel,
        icon: Icons.swap_vert_rounded,
      ),
      _TeamMetric(
        label: 'Clean sheets',
        value: '${statistics.cleanSheets}',
        icon: Icons.lock_outline_rounded,
      ),
      _TeamMetric(
        label: 'Marqués / match',
        value: _average(statistics.goalsForPerMatch),
        icon: Icons.trending_up_rounded,
      ),
      _TeamMetric(
        label: 'Encaissés / match',
        value: _average(statistics.goalsAgainstPerMatch),
        icon: Icons.trending_down_rounded,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 3 : 2;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: _TeamMetricCard(metric: metric),
              ),
          ],
        );
      },
    );
  }
}

class _TeamMetric {
  const _TeamMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}

class _TeamMetricCard extends StatelessWidget {
  const _TeamMetricCard({required this.metric});

  final _TeamMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(metric.icon, color: colors.primary),
            const SizedBox(height: 16),
            Text(
              metric.value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              metric.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Message plein écran (vide / erreur) rafraîchissable par tirer-lâcher.
class _ScrollableMessage extends StatelessWidget {
  const _ScrollableMessage({required this.message, required this.onRefresh});

  final String message;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(message),
            ),
          ),
        ],
      ),
    );
  }
}

const _statNameFlex = 7;
const _statValueFlex = 2;

enum _StatCol { name, played, wins, draws, losses, main, hdm }

class _StatisticsHeaderRow extends StatelessWidget {
  const _StatisticsHeaderRow({
    required this.sort,
    required this.descending,
    required this.onSort,
  });

  final _StatCol? sort;
  final bool descending;
  final void Function(_StatCol) onSort;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white70,
          fontWeight: FontWeight.w800,
        );

    Widget cell(String label, _StatCol col) => SortableHeaderCell(
          label: label,
          flex: _statValueFlex,
          active: sort == col,
          descending: descending,
          onTap: () => onSort(col),
          style: style,
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 11, 12, 11),
      child: Row(
        children: [
          SortableHeaderCell(
            label: 'Joueur',
            flex: _statNameFlex,
            align: TextAlign.start,
            active: sort == _StatCol.name,
            descending: descending,
            onTap: () => onSort(_StatCol.name),
            style: style,
          ),
          cell('J', _StatCol.played),
          cell('G', _StatCol.wins),
          cell('N', _StatCol.draws),
          cell('P', _StatCol.losses),
          cell('B/CS', _StatCol.main),
          cell('HDM', _StatCol.hdm),
        ],
      ),
    );
  }
}

class _StatisticsDataRow extends StatelessWidget {
  const _StatisticsDataRow({required this.rank, required this.player});

  final int rank;
  final PlayerStatistics player;

  @override
  Widget build(BuildContext context) {
    final mainStat = player.isGoalkeeper ? player.cleanSheets : player.goals;

    Widget value(int v) => Expanded(
          flex: _statValueFlex,
          child: Text(
            '$v',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            flex: _statNameFlex,
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: Text(
                    '$rank',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white54,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: NameWithBadges(
                    profileId: player.profileId,
                    name: player.playerName,
                    badgeSize: 18,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
          ),
          value(player.matchesPlayed ?? 0),
          value(player.wins ?? 0),
          value(player.draws ?? 0),
          value(player.losses ?? 0),
          value(mainStat),
          value(player.hdm ?? 0),
        ],
      ),
    );
  }
}
