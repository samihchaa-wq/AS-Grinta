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
          loading: () => const ListView(
            children: [
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
                      Text(
                        error.toString(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () =>
                            ref.invalidate(careerStatisticsProvider),
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          data: (statistics) {
            if (statistics.isEmpty) {
              return const ListView(
                padding: EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Aucune statistique individuelle disponible.'),
                    ),
                  ),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Classement carrière',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Les statistiques historiques individuelles commencent avec les matchs saisis dans l’application.',
                ),
                const SizedBox(height: 16),
                ...statistics.indexed.map((entry) {
                  final rank = entry.$1 + 1;
                  final player = entry.$2;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ExpansionTile(
                      leading: CircleAvatar(child: Text('$rank')),
                      title: Text(player.name),
                      subtitle: Text(
                        '${player.matches} match(s) • ${player.minutesPlayed} min',
                      ),
                      trailing: Wrap(
                        spacing: 10,
                        children: [
                          _StatValue(label: 'B', value: player.goals),
                          _StatValue(label: 'P', value: player.assists),
                          _StatValue(label: 'M', value: player.motm),
                        ],
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        Wrap(
                          spacing: 18,
                          runSpacing: 12,
                          children: [
                            _DetailStat(
                              icon: Icons.timer_outlined,
                              label: 'Minutes',
                              value: player.minutesPlayed,
                            ),
                            _DetailStat(
                              icon: Icons.sports_soccer_outlined,
                              label: 'Titularisations',
                              value: player.starts,
                            ),
                            _DetailStat(
                              icon: Icons.swap_horiz,
                              label: 'Entrées en jeu',
                              value: player.substituteAppearances,
                            ),
                            _DetailStat(
                              icon: Icons.shield_outlined,
                              label: 'Clean sheets',
                              value: player.cleanSheets,
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatValue extends StatelessWidget {
  const _StatValue({required this.label, required this.value});

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

class _DetailStat extends StatelessWidget {
  const _DetailStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$value', style: Theme.of(context).textTheme.titleMedium),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
