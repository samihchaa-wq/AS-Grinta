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
        final outfieldPlayers = data.players
            .where((player) => !player.isGoalkeeper)
            .toList(growable: false);
        final goalkeepers = data.players
            .where((player) => player.isGoalkeeper)
            .toList(growable: false);

        return RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _PeriodHeader(period: period, label: data.label),
              const SizedBox(height: 16),
              if (outfieldPlayers.isNotEmpty)
                _StatisticsSection(
                  title: 'Joueurs de champ',
                  icon: Icons.sports_soccer,
                  players: outfieldPlayers,
                ),
              if (outfieldPlayers.isNotEmpty && goalkeepers.isNotEmpty)
                const SizedBox(height: 18),
              if (goalkeepers.isNotEmpty)
                _StatisticsSection(
                  title: 'Gardien',
                  icon: Icons.sports_handball_outlined,
                  players: goalkeepers,
                ),
              if (data.players.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Aucune statistique disponible.'),
                  ),
                ),
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
  const _PeriodHeader({required this.period, required this.label});

  final StatisticsPeriod period;
  final String label;

  String get _description => switch (period) {
        StatisticsPeriod.current =>
          'J/G/N/P, buts, HDM et clean sheets mis à jour après chaque match validé.',
        StatisticsPeriod.previous =>
          'Classements corrigés de la saison terminée 2025-2026.',
        StatisticsPeriod.allTime =>
          'Cumul de toutes les saisons, saison actuelle incluse en temps réel.',
      };

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  _description,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatisticsSection extends StatelessWidget {
  const _StatisticsSection({
    required this.title,
    required this.icon,
    required this.players,
  });

  final String title;
  final IconData icon;
  final List<PlayerStatistics> players;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1D3B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF4B6FFF).withValues(alpha: .30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFF79A4FF)),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final player in players) _PlayerStatisticsCard(player: player),
        ],
      ),
    );
  }
}

class _PlayerStatisticsCard extends StatelessWidget {
  const _PlayerStatisticsCard({required this.player});

  final PlayerStatistics player;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF14264D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _RankBadge(rank: player.rank),
              const SizedBox(width: 11),
              Expanded(
                child: NameWithBadges(
                  profileId: player.profileId,
                  name: player.playerName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (!player.hasHistoricalBreakdown)
                _CurrentMetric(
                  label: player.isGoalkeeper ? 'Clean sheets' : 'Buts',
                  value:
                      player.isGoalkeeper ? player.cleanSheets : player.goals,
                ),
            ],
          ),
          if (player.hasHistoricalBreakdown) ...[
            const SizedBox(height: 12),
            _historicalMetricsRow(),
          ],
        ],
      ),
    );
  }

  Widget _historicalMetricsRow() {
    final metrics = _historicalMetrics();
    final children = <Widget>[];

    for (var index = 0; index < metrics.length; index++) {
      if (index > 0) children.add(const SizedBox(width: 5));
      children.add(Expanded(child: metrics[index]));
    }

    return Row(children: children);
  }

  List<Widget> _historicalMetrics() {
    final metrics = <Widget>[
      _MetricTile(label: 'J', value: player.matchesPlayed ?? 0),
      _MetricTile(label: 'G', value: player.wins ?? 0),
      _MetricTile(label: 'N', value: player.draws ?? 0),
      _MetricTile(label: 'P', value: player.losses ?? 0),
    ];

    if (player.isGoalkeeper) {
      metrics.addAll([
        _MetricTile(label: 'HDM', value: player.hdm ?? 0),
        _MetricTile(label: 'CS', value: player.cleanSheets),
      ]);
    } else {
      metrics.addAll([
        _MetricTile(label: 'Buts', value: player.goals),
        _MetricTile(label: 'HDM', value: player.hdm ?? 0),
      ]);
    }
    return metrics;
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF4B6FFF).withValues(alpha: .18),
        border: Border.all(
          color: const Color(0xFF79A4FF).withValues(alpha: .55),
        ),
      ),
      child: Text('$rank', style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}

class _CurrentMetric extends StatelessWidget {
  const _CurrentMetric({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF4B6FFF).withValues(alpha: .16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF79A4FF),
                ),
          ),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 18,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$value',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: Colors.white60),
            ),
          ),
        ],
      ),
    );
  }
}
