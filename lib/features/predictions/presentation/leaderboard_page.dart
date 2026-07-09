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
                  child: Text(error.toString()),
                ),
              ),
            ],
          ),
          data: (entries) {
            if (entries.isEmpty) {
              return const ListView(
                padding: EdgeInsets.all(16),
                children: [
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
                      'Total = points des matchs + points des pronostics de saison. Les pourcentages sont uniquement indicatifs.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...entries.indexed.map((entry) {
                  final rank = entry.$1 + 1;
                  final item = entry.$2;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: CircleAvatar(child: Text('$rank')),
                      title: Text(item.name),
                      subtitle: Text(
                        'Matchs ${item.matchPoints.toStringAsFixed(1)} • Saison ${item.seasonPoints.toStringAsFixed(1)}',
                      ),
                      trailing: Text(
                        item.totalPoints.toStringAsFixed(1),
                        style: Theme.of(context).textTheme.titleLarge,
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
