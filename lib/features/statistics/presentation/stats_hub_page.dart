import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/sticky_header_table.dart';
import 'package:as_grinta/features/badges/presentation/name_with_badges.dart';
import 'package:as_grinta/features/predictions/presentation/pronos_hub_page.dart';
import 'package:as_grinta/features/statistics/data/statistics_repository.dart';
import 'package:as_grinta/features/statistics/presentation/team_statistics_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _StatsSection { rankings, players, team }

class StatsHubPage extends StatefulWidget {
  const StatsHubPage({super.key, this.initialSection, this.initialRankingView});

  final String? initialSection;
  final String? initialRankingView;

  @override
  State<StatsHubPage> createState() => _StatsHubPageState();
}

class _StatsHubPageState extends State<StatsHubPage> {
  late _StatsSection _section = switch (widget.initialSection) {
    'players' => _StatsSection.players,
    'team' => _StatsSection.team,
    _ => _StatsSection.rankings,
  };
  StatisticsPeriod _period = StatisticsPeriod.current;

  @override
  Widget build(BuildContext context) {
    final hasPeriod = _section != _StatsSection.rankings;
    return Scaffold(
      appBar: GrintaAppBar(
        title: const Text('Stats'),
        actions: grintaHomeActions(context),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_StatsSection>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: _StatsSection.rankings,
                    icon: Icon(Icons.leaderboard_outlined),
                    label: Text('Classement'),
                  ),
                  ButtonSegment(
                    value: _StatsSection.players,
                    icon: Icon(Icons.groups_2_outlined),
                    label: Text('Stats joueurs'),
                  ),
                  ButtonSegment(
                    value: _StatsSection.team,
                    icon: Icon(Icons.shield_outlined),
                    label: Text('Stat équipe'),
                  ),
                ],
                selected: {_section},
                onSelectionChanged: (value) {
                  setState(() => _section = value.first);
                },
              ),
            ),
          ),
          if (hasPeriod)
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
                  onSelectionChanged: (value) {
                    setState(() => _period = value.first);
                  },
                ),
              ),
            ),
          Expanded(
            child: switch (_section) {
              _StatsSection.rankings => RankingsPanel(
                  initialView: widget.initialRankingView,
                ),
              _StatsSection.players => _PlayersPanel(period: _period),
              _StatsSection.team => TeamStatisticsPanel(period: _period),
            },
          ),
        ],
      ),
    );
  }
}

enum _PlayerStatCol { name, played, wins, draws, losses, goals, hdm }

const _playerNameFlex = 5;
const _playerValueFlex = 1;

class _PlayersPanel extends ConsumerStatefulWidget {
  const _PlayersPanel({required this.period});

  final StatisticsPeriod period;

  @override
  ConsumerState<_PlayersPanel> createState() => _PlayersPanelState();
}

class _PlayersPanelState extends ConsumerState<_PlayersPanel> {
  _PlayerStatCol? _sort;
  bool _descending = true;

  void _onSort(_PlayerStatCol column) {
    setState(() {
      if (_sort == column) {
        _descending = !_descending;
      } else {
        _sort = column;
        _descending = column != _PlayerStatCol.name;
      }
    });
  }

  num _value(_PlayerStatCol column, PlayerStatistics player) {
    return switch (column) {
      _PlayerStatCol.played => player.matchesPlayed ?? 0,
      _PlayerStatCol.wins => player.wins ?? 0,
      _PlayerStatCol.draws => player.draws ?? 0,
      _PlayerStatCol.losses => player.losses ?? 0,
      _PlayerStatCol.goals => player.goals,
      _PlayerStatCol.hdm => player.hdm ?? 0,
      _PlayerStatCol.name => 0,
    };
  }

  Future<void> _refresh() async {
    ref.invalidate(statisticsPeriodProvider(widget.period));
    await ref.read(statisticsPeriodProvider(widget.period).future);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(statisticsPeriodProvider(widget.period));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _Message(
        title: 'Statistiques indisponibles',
        message: humanizeError(error),
        onRefresh: _refresh,
      ),
      data: (data) {
        if (data.players.isEmpty) {
          return _Message(
            title: 'Pas encore de statistiques',
            message: 'Les stats apparaîtront après le premier match validé.',
            onRefresh: _refresh,
          );
        }

        final players = [...data.players];
        final sort = _sort;
        if (sort != null) {
          players.sort((a, b) {
            final comparison = sort == _PlayerStatCol.name
                ? a.playerName
                    .toLowerCase()
                    .compareTo(b.playerName.toLowerCase())
                : _value(sort, a).compareTo(_value(sort, b));
            if (comparison == 0) {
              return a.playerName
                  .toLowerCase()
                  .compareTo(b.playerName.toLowerCase());
            }
            return _descending ? -comparison : comparison;
          });
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: StickyHeaderTableCard(
            minWidth: 0,
            onRefresh: _refresh,
            header: _PlayersHeaderRow(
              sort: _sort,
              descending: _descending,
              onSort: _onSort,
            ),
            rows: [
              for (var index = 0; index < players.length; index++)
                _PlayersDataRow(
                  rank: index + 1,
                  player: players[index],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PlayersHeaderRow extends StatelessWidget {
  const _PlayersHeaderRow({
    required this.sort,
    required this.descending,
    required this.onSort,
  });

  final _PlayerStatCol? sort;
  final bool descending;
  final ValueChanged<_PlayerStatCol> onSort;

  @override
  Widget build(BuildContext context) {
    final style = grintaTableHeaderTextStyle(context);

    Widget valueCell(String label, _PlayerStatCol column) {
      return SortableHeaderCell(
        label: label,
        flex: _playerValueFlex,
        active: sort == column,
        descending: descending,
        onTap: () => onSort(column),
        style: style,
      );
    }

    return Padding(
      padding: grintaTableHeaderPadding,
      child: Row(
        children: [
          SortableHeaderCell(
            label: 'Joueur',
            flex: _playerNameFlex,
            align: TextAlign.start,
            active: sort == _PlayerStatCol.name,
            descending: descending,
            onTap: () => onSort(_PlayerStatCol.name),
            style: style,
          ),
          valueCell('J', _PlayerStatCol.played),
          valueCell('G', _PlayerStatCol.wins),
          valueCell('N', _PlayerStatCol.draws),
          valueCell('P', _PlayerStatCol.losses),
          valueCell('B', _PlayerStatCol.goals),
          valueCell('HDM', _PlayerStatCol.hdm),
        ],
      ),
    );
  }
}

class _PlayersDataRow extends StatelessWidget {
  const _PlayersDataRow({required this.rank, required this.player});

  final int rank;
  final PlayerStatistics player;

  @override
  Widget build(BuildContext context) {
    Widget value(int number) {
      return Expanded(
        flex: _playerValueFlex,
        child: Text(
          '$number',
          textAlign: TextAlign.center,
          style: grintaTableCellTextStyle(context),
        ),
      );
    }

    return Padding(
      padding: grintaTableRowPadding,
      child: Row(
        children: [
          Expanded(
            flex: _playerNameFlex,
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '$rank',
                    style: grintaTableRankTextStyle(context),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: NameWithBadges(
                    profileId: player.profileId,
                    name: player.playerName,
                    badgeSize: 18,
                    style: grintaTableCellTextStyle(
                      context,
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
          value(player.goals),
          value(player.hdm ?? 0),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    required this.message,
    required this.onRefresh,
  });

  final String title;
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
            child: GrintaEmptyState(
              icon: Icons.bar_chart_rounded,
              title: title,
              message: message,
            ),
          ),
        ],
      ),
    );
  }
}
