import 'package:as_grinta/features/statistics/data/statistics_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StatisticsPageV2 extends ConsumerWidget {
  const StatisticsPageV2({super.key});

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
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 220),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (_, __) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
            children: [
              const Icon(Icons.cloud_off_outlined, size: 52),
              const SizedBox(height: 16),
              Text(
                'Statistiques temporairement indisponibles',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Center(
                child: FilledButton.icon(
                  onPressed: () => ref.invalidate(careerStatisticsProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualiser'),
                ),
              ),
            ],
          ),
          data: (all) {
            if (all.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
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

            final outfield = all.where((player) => !player.isGoalkeeper).toList();
            final goalkeepers = all.where((player) => player.isGoalkeeper).toList()
              ..sort((a, b) => b.cleanSheets.compareTo(a.cleanSheets));
            final topGoals = [...outfield]
              ..sort((a, b) => b.goals.compareTo(a.goals));
            final topAssists = [...outfield]
              ..sort((a, b) => b.assists.compareTo(a.assists));
            final topPenaltyFaults = [...all]
              ..sort((a, b) => b.penaltyFaults.compareTo(a.penaltyFaults));
            final topMotm = [...all]
              ..sort((a, b) => b.motm.compareTo(a.motm));
            final alphabetical = [...all]
              ..sort((a, b) => a.sortName.compareTo(b.sortName));

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'Les statistiques individuelles commencent avec les feuilles de match postérieures au lancement de cette version.',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _RankingSection(
                  title: 'Classement buteurs',
                  icon: Icons.sports_soccer_rounded,
                  fullRanking: topGoals.where((p) => p.goals > 0).toList(),
                  value: (p) => p.goals,
                  unit: 'but',
                ),
                const SizedBox(height: 24),
                _RankingSection(
                  title: 'Classement passeurs décisifs',
                  icon: Icons.swap_calls_rounded,
                  fullRanking:
                      topAssists.where((p) => p.assists > 0).toList(),
                  value: (p) => p.assists,
                  unit: 'passe',
                ),
                const SizedBox(height: 24),
                _RankingSection(
                  title: 'Classement fautes provoquant un penalty',
                  icon: Icons.warning_amber_rounded,
                  fullRanking: topPenaltyFaults
                      .where((p) => p.penaltyFaults > 0)
                      .toList(),
                  value: (p) => p.penaltyFaults,
                  unit: 'faute',
                ),
                const SizedBox(height: 24),
                _RankingSection(
                  title: 'Classement hommes du match',
                  icon: Icons.emoji_events_rounded,
                  fullRanking: topMotm.where((p) => p.motm > 0).toList(),
                  value: (p) => p.motm,
                  unit: 'HDM',
                ),
                const SizedBox(height: 24),
                // Seule exception à la règle « un joueur à 0 n'apparaît
                // pas » : les gardiens restent visibles ici, même sans
                // clean sheet.
                _RankingSection(
                  title: 'Classement clean sheets',
                  icon: Icons.shield_outlined,
                  fullRanking: goalkeepers,
                  value: (p) => p.cleanSheets,
                  unit: 'clean sheet',
                  emptyLabel: 'Aucun gardien enregistré.',
                ),
                const SizedBox(height: 24),
                const _SectionTitle(
                  icon: Icons.bar_chart_rounded,
                  label: 'Statistiques individuelles',
                ),
                const SizedBox(height: 8),
                ...alphabetical.map((player) => _PlayerCard(player: player)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RankingSection extends StatefulWidget {
  const _RankingSection({
    required this.title,
    required this.icon,
    required this.fullRanking,
    required this.value,
    required this.unit,
    this.emptyLabel = 'Aucune donnée enregistrée.',
  });

  final String title;
  final IconData icon;
  final List<PlayerStatistics> fullRanking;
  final int Function(PlayerStatistics) value;
  final String unit;
  final String emptyLabel;

  @override
  State<_RankingSection> createState() => _RankingSectionState();
}

class _RankingSectionState extends State<_RankingSection> {
  bool _expanded = false;

  String _line(PlayerStatistics player) {
    final count = widget.value(player);
    final plural = count > 1 && !widget.unit.endsWith('HDM') ? 's' : '';
    return '$count ${widget.unit}$plural';
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        _expanded ? widget.fullRanking : widget.fullRanking.take(5).toList();
    final hasMore = widget.fullRanking.length > 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(icon: widget.icon, label: widget.title),
        const SizedBox(height: 8),
        if (visible.isEmpty)
          Text(widget.emptyLabel)
        else ...[
          ...visible.indexed.map(
            (entry) => Card(
              child: ListTile(
                leading: CircleAvatar(child: Text('${entry.$1 + 1}')),
                title: Text(entry.$2.displayName),
                trailing: Text(
                  _line(entry.$2),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ),
          if (hasMore)
            Center(
              child: IconButton(
                tooltip: _expanded
                    ? 'Réduire le classement'
                    : 'Voir tout le classement',
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 30,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.player});

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
        title: Text(player.displayName),
        subtitle: Text(
          '${player.matches} match${player.matches > 1 ? 's' : ''}',
        ),
        trailing: Wrap(
          spacing: 8,
          children: [
            if (!player.isGoalkeeper) ...[
              _Badge(label: 'B', value: player.goals),
              _Badge(label: 'P', value: player.assists),
            ],
            _Badge(label: 'FP', value: player.penaltyFaults),
            _Badge(label: 'M', value: player.motm),
            if (player.isGoalkeeper)
              _Badge(label: 'CS', value: player.cleanSheets),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              _Detail(label: 'Matchs', value: player.matches),
              if (!player.isGoalkeeper) ...[
                _Detail(label: 'Buts', value: player.goals),
                _Detail(label: 'Passes D.', value: player.assists),
              ],
              _Detail(
                label: 'Fautes provoquant un penalty',
                value: player.penaltyFaults,
              ),
              _Detail(label: 'HDM', value: player.motm),
              if (player.isGoalkeeper)
                _Detail(label: 'Clean sheets', value: player.cleanSheets),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.titleLarge),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.value});

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

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: Theme.of(context).textTheme.titleMedium),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
