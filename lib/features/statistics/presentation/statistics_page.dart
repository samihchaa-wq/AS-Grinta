import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/sticky_header_table.dart';
import 'package:as_grinta/features/badges/presentation/name_with_badges.dart';
import 'package:as_grinta/features/statistics/data/statistics_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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
          Expanded(child: _StatisticsPeriodView(period: _period)),
        ],
      ),
    );
  }
}

class _StatisticsPeriodView extends ConsumerWidget {
  const _StatisticsPeriodView({required this.period});

  final StatisticsPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(statisticsPeriodProvider(period));

    return dataAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ScrollableMessage(
        message: humanizeError(error),
        onRefresh: () => _refresh(ref),
      ),
      data: (data) {
        if (data.players.isEmpty) {
          return _ScrollableMessage(
            message: 'Aucune statistique disponible.',
            onRefresh: () => _refresh(ref),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: StickyHeaderTableCard(
            onRefresh: () => _refresh(ref),
            header: const _StatisticsHeaderRow(),
            rows: [
              for (final player in data.players)
                _StatisticsDataRow(player: player),
            ],
          ),
        );
      },
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(statisticsPeriodProvider(period));
    await ref.read(statisticsPeriodProvider(period).future);
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

class _StatisticsHeaderRow extends StatelessWidget {
  const _StatisticsHeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white70,
          fontWeight: FontWeight.w800,
        );

    Widget cell(String label) => Expanded(
          flex: _statValueFlex,
          child: Text(label, style: style, textAlign: TextAlign.center),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(flex: _statNameFlex, child: Text('Joueur', style: style)),
          cell('J'),
          cell('G'),
          cell('N'),
          cell('P'),
          cell('B/CS'),
          cell('HDM'),
        ],
      ),
    );
  }
}

class _StatisticsDataRow extends StatelessWidget {
  const _StatisticsDataRow({required this.player});

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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: _statNameFlex,
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${player.rank}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white54,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: NameWithBadges(
                    profileId: player.profileId,
                    name: player.playerName,
                    badgeSize: 20,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
