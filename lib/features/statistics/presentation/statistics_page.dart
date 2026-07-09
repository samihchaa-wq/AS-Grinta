import 'package:as_grinta/features/statistics/data/statistics_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StatisticsPage extends ConsumerWidget {
  const StatisticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statisticsAsync = ref.watch(careerStatisticsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(careerStatisticsProvider);
          await ref.read(careerStatisticsProvider.future);
        },
        child: statisticsAsync.when(
          loading: () => ListView(
            children: const [
              SizedBox(height: 220),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(error.toString(), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => ref.invalidate(careerStatisticsProvider),
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          data: (all) {
            if (all.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Aucune statistique disponible.'),
                    ),
                  ),
                ],
              );
            }

            final outfieldPlayers = all.where((p) => !p.isGoalkeeper).toList();
            final top5Goals = [...outfieldPlayers]
              ..sort((a, b) => b.goals.compareTo(a.goals));
            final top5Assists = [...outfieldPlayers]
              ..sort((a, b) => b.assists.compareTo(a.assists));
            final top5Motm = [...all]
              ..sort((a, b) => b.motm.compareTo(a.motm));
            final goalkeepers = all.where((p) => p.isGoalkeeper).toList()
              ..sort((a, b) => b.cleanSheets.compareTo(a.cleanSheets));
            final alphabetical = [...all]
              ..sort((a, b) => a.sortName.compareTo(b.sortName));

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                const _SectionHeader(
                  icon: Icons.sports_soccer_rounded,
                  label: 'Top 5 Buteurs',
                ),
                const SizedBox(height: 8),
                ..._rankingRows(
                  top5Goals.where((p) => p.goals > 0).take(5).toList(),
                  value: (p) => p.goals,
                  unit: (v) => 'but${v > 1 ? 's' : ''}',
                  emptyLabel: 'Aucun but enregistré',
                ),
                const SizedBox(height: 24),
                const _SectionHeader(
                  icon: Icons.swap_calls_rounded,
                  label: 'Top 5 Passeurs décisifs',
                ),
                const SizedBox(height: 8),
                ..._rankingRows(
                  top5Assists.where((p) => p.assists > 0).take(5).toList(),
                  value: (p) => p.assists,
                  unit: (v) => 'passe${v > 1 ? 's' : ''}',
                  emptyLabel: 'Aucune passe décisive enregistrée',
                ),
                const SizedBox(height: 24),
                const _SectionHeader(
                  icon: Icons.emoji_events_rounded,
                  label: 'Top 5 Hommes du Match',
                ),
                const SizedBox(height: 8),
                ..._rankingRows(
                  top5Motm.where((p) => p.motm > 0).take(5).toList(),
                  value: (p) => p.motm,
                  unit: (_) => 'HDM',
                  emptyLabel: 'Aucun Homme du Match enregistré',
                ),
                const SizedBox(height: 24),
                _SectionHeader(
                  icon: Icons.shield_outlined,
                  label: 'Clean sheets gardien${goalkeepers.length > 1 ? 's' : ''}',
                ),
                const SizedBox(height: 8),
                if (goalkeepers.isEmpty)
                  const _EmptyChip('Aucun gardien enregistré')
                else
                  ...goalkeepers.map(
                    (gk) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.sports_handball),
                        ),
                        title: Text(gk.displayName),
                        subtitle: Text(
                          '${gk.matches} match${gk.matches > 1 ? 's' : ''} • ${gk.minutesPlayed} min',
                        ),
                        trailing: _BigStat(value: gk.cleanSheets, label: 'CS'),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                const _SectionHeader(
                  icon: Icons.bar_chart_rounded,
                  label: 'Statistiques individuelles',
                ),
                const SizedBox(height: 4),
                Text(
                  'Classées par surnom, A → Z',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                ...alphabetical.map((player) => _PlayerStatsCard(player: player)),
              ],
            );
          },
        ),
      ),
    );
  }

  static List<Widget> _rankingRows(
    List<PlayerStatistics> players, {
    required int Function(PlayerStatistics) value,
    required String Function(int) unit,
    required String emptyLabel,
  }) {
    if (players.isEmpty) return [ _EmptyChip(emptyLabel) ];
    return players.indexed
        .map(
          (e) => _TopRankRow(
            rank: e.$1 + 1,
            name: e.$2.displayName,
            value: value(e.$2),
            unit: unit(value(e.$2)),
          ),
        )
        .toList();
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}

class _EmptyChip extends StatelessWidget {
  const _EmptyChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _TopRankRow extends StatelessWidget {
  const _TopRankRow({
    required this.rank,
    required this.name,
    required this.value,
    required this.unit,
  });

  final int rank;
  final String name;
  final int value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: CircleAvatar(child: Text('$rank')),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text('$value $unit'),
      ),
    );
  }
}

class _BigStat extends StatelessWidget {
  const _BigStat({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _PlayerStatsCard extends StatelessWidget {
  const _PlayerStatsCard({required this.player});
  final PlayerStatistics player;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          child: Icon(
            player.isGoalkeeper
                ? Icons.sports_handball
                : Icons.sports_soccer_rounded,
          ),
        ),
        title: Text(
          player.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${player.matches} match${player.matches > 1 ? 's' : ''} • ${player.minutesPlayed} min',
        ),
        trailing: Wrap(
          spacing: 10,
          children: [
            if (!player.isGoalkeeper) ...[
              _StatBadge(label: 'B', value: player.goals),
              _StatBadge(label: 'P', value: player.assists),
            ],
            _StatBadge(label: 'M', value: player.motm),
            if (player.isGoalkeeper)
              _StatBadge(label: 'CS', value: player.cleanSheets),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              _DetailRow(
                icon: Icons.timer_outlined,
                label: 'Minutes',
                value: '${player.minutesPlayed}',
              ),
              if (!player.isGoalkeeper) ...[
                _DetailRow(
                  icon: Icons.sports_soccer_outlined,
                  label: 'Buts',
                  value: '${player.goals}',
                ),
                _DetailRow(
                  icon: Icons.swap_calls_rounded,
                  label: 'Passes D.',
                  value: '${player.assists}',
                ),
              ],
              _DetailRow(
                icon: Icons.emoji_events_outlined,
                label: 'HDM',
                value: '${player.motm}',
              ),
              if (player.isGoalkeeper)
                _DetailRow(
                  icon: Icons.shield_outlined,
                  label: 'Clean sheets',
                  value: '${player.cleanSheets}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$value', style: Theme.of(context).textTheme.titleMedium),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: Theme.of(context).textTheme.titleMedium),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
