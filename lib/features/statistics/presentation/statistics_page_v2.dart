import 'package:as_grinta/core/utils/app_errors.dart';
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
          error: (error, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
            children: [
              const Icon(Icons.cloud_off_outlined, size: 52),
              const SizedBox(height: 16),
              Text(
                humanizeError(error),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
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

            // Classement des buteurs : buts décroissants, puis nom.
            final scorers = [...all]..sort((a, b) {
                final byGoals = b.goals.compareTo(a.goals);
                if (byGoals != 0) return byGoals;
                return a.sortName.compareTo(b.sortName);
              });
            final goalkeepers = all.where((p) => p.isGoalkeeper).toList()
              ..sort((a, b) => b.cleanSheets.compareTo(a.cleanSheets));

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _ScorerRanking(scorers: scorers),
                const SizedBox(height: 24),
                const _SectionTitle(
                  icon: Icons.shield_outlined,
                  label: 'Clean sheets',
                ),
                const SizedBox(height: 8),
                if (goalkeepers.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Aucun gardien enregistré.'),
                    ),
                  )
                else
                  ...goalkeepers.map(
                    (player) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.sports_handball),
                        ),
                        title: Text(player.displayName),
                        trailing: _Badge(
                          label: 'clean sheets',
                          value: player.cleanSheets,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ScorerRanking extends StatefulWidget {
  const _ScorerRanking({required this.scorers});

  final List<PlayerStatistics> scorers;

  @override
  State<_ScorerRanking> createState() => _ScorerRankingState();
}

class _ScorerRankingState extends State<_ScorerRanking> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    // Un joueur à 0 but n'apparaît pas dans le classement des buteurs.
    final ranked = widget.scorers.where((p) => p.goals > 0).toList();
    final visible = _expanded ? ranked : ranked.take(5).toList();
    final hasMore = ranked.length > 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          icon: Icons.sports_soccer_rounded,
          label: 'Classement buteurs',
        ),
        const SizedBox(height: 8),
        if (visible.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Aucun but marqué pour l’instant.'),
            ),
          )
        else ...[
          ...visible.indexed.map(
            (entry) => Card(
              child: ListTile(
                leading: CircleAvatar(child: Text('${entry.$1 + 1}')),
                title: Text(entry.$2.displayName),
                trailing: Text(
                  '${entry.$2.goals} but${entry.$2.goals > 1 ? 's' : ''}',
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
