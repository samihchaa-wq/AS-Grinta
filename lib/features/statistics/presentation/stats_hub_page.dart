import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
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

class _PlayersPanel extends ConsumerWidget {
  const _PlayersPanel({required this.period});

  final StatisticsPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(statisticsPeriodProvider(period));
    Future<void> refresh() async {
      ref.invalidate(statisticsPeriodProvider(period));
      await ref.read(statisticsPeriodProvider(period).future);
    }

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _Message(
        title: 'Statistiques indisponibles',
        message: humanizeError(error),
        onRefresh: refresh,
      ),
      data: (data) {
        if (data.players.isEmpty) {
          return _Message(
            title: 'Pas encore de statistiques',
            message: 'Les stats apparaîtront après le premier match validé.',
            onRefresh: refresh,
          );
        }
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: data.players.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final player = data.players[index];
              final main = player.isGoalkeeper
                  ? '${player.cleanSheets} CS'
                  : '${player.goals} B';
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Expanded(
                        child: NameWithBadges(
                          profileId: player.profileId,
                          name: player.playerName,
                          badgeSize: 18,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      Text(
                        '${player.matchesPlayed ?? 0} J · '
                        '${player.wins ?? 0} G · $main · ${player.hdm ?? 0} HDM',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
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
