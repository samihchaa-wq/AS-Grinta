import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/sticky_header_table.dart';
import 'package:as_grinta/features/badges/presentation/name_with_badges.dart';
import 'package:as_grinta/features/statistics/data/statistics_repository.dart';
import 'package:as_grinta/features/statistics/presentation/team_statistics_panel.dart';
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
              _StatisticsSection.team => TeamStatisticsPanel(period: _period),
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
        icon: Icons.wifi_off_rounded,
        title: 'Statistiques indisponibles',
        message: humanizeError(error),
        tone: GrintaEmptyTone.alert,
        onRefresh: _refresh,
      ),
      data: (data) {
        if (data.players.isEmpty) {
          return _ScrollableMessage(
            icon: Icons.bar_chart_rounded,
            title: 'Pas encore de statistiques',
            message: 'Les stats des joueurs apparaîtront après le premier '
                'match validé.',
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

/// Message plein écran (vide / erreur) rafraîchissable par tirer-lâcher.
class _ScrollableMessage extends StatelessWidget {
  const _ScrollableMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRefresh,
    this.tone = GrintaEmptyTone.neutral,
  });

  final IconData icon;
  final String title;
  final String message;
  final GrintaEmptyTone tone;
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
              icon: icon,
              title: title,
              message: message,
              tone: tone,
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
