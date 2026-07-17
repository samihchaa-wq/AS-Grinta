import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/badges/presentation/name_with_badges.dart';
import 'package:as_grinta/features/statistics/data/statistics_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StatisticsPage extends StatelessWidget {
  const StatisticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: GrintaAppBar(
          title: const Text('Statistiques'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Saison actuelle'),
              Tab(text: 'Saison précédente'),
              Tab(text: 'Toutes saisons'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _StatisticsPeriodView(period: StatisticsPeriod.current),
            _StatisticsPeriodView(period: StatisticsPeriod.previous),
            _StatisticsPeriodView(period: StatisticsPeriod.allTime),
          ],
        ),
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
      error: (error, _) => RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(humanizeError(error)),
              ),
            ),
          ],
        ),
      ),
      data: (data) {
        return RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _PeriodHeader(label: data.label),
              const SizedBox(height: 16),
              if (data.players.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Aucune statistique disponible.'),
                  ),
                )
              else
                _StatisticsTable(players: data.players),
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

class _PeriodHeader extends StatelessWidget {
  const _PeriodHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1D3B),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF4B6FFF).withValues(alpha: .38),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF4B6FFF).withValues(alpha: .14),
            ),
            child: const Icon(
              Icons.query_stats_rounded,
              color: Color(0xFF79A4FF),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tableau des statistiques, même présentation que les « Classements » : un
/// cartouche unique, une ligne d'en-tête, des lignes séparées par des filets.
class _StatisticsTable extends StatelessWidget {
  const _StatisticsTable({required this.players});

  final List<PlayerStatistics> players;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const _StatisticsHeaderRow(),
          const Divider(height: 1),
          for (var index = 0; index < players.length; index++) ...[
            _StatisticsDataRow(player: players[index]),
            if (index != players.length - 1) const Divider(height: 1),
          ],
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
