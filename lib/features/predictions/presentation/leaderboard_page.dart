import 'package:as_grinta/features/predictions/data/leaderboard_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LeaderboardPage extends ConsumerWidget {
  const LeaderboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaderboardAsync = ref.watch(leaderboardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Classement général')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(leaderboardProvider);
          await ref.read(leaderboardProvider.future);
        },
        child: leaderboardAsync.when(
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
                  child: Text(error.toString()),
                ),
              ),
            ],
          ),
          data: (entries) {
            if (entries.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Aucun point calculable pour le moment.'),
                    ),
                  ),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Le classement est ordonné par la somme directe des points '
                      'matchs et saison. Les pourcentages montrent la progression '
                      'par rapport au maximum théorique disponible.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...entries.indexed.map((entry) {
                  final rank = entry.$1 + 1;
                  final item = entry.$2;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(child: Text('$rank')),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item.name,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              Text(
                                item.totalPoints.toStringAsFixed(1),
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Matchs : ${item.matchPoints.toStringAsFixed(1)} / '
                            '${item.matchMaxPoints.toStringAsFixed(1)} '
                            '(${item.matchPercentage.toStringAsFixed(1)} %)',
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: (item.matchPercentage / 100)
                                .clamp(0.0, 1.0)
                                .toDouble(),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Saison : ${item.seasonPoints.toStringAsFixed(1)} / '
                            '${item.seasonMaxPoints.toStringAsFixed(1)} '
                            '(${item.seasonPercentage.toStringAsFixed(1)} %)',
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: (item.seasonPercentage / 100)
                                .clamp(0.0, 1.0)
                                .toDouble(),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Progression théorique globale : '
                            '${item.totalPercentage.toStringAsFixed(1)} %',
                          ),
                        ],
                      ),
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
