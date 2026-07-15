import 'package:as_grinta/features/predictions/data/leaderboard_repository.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _RankingType { match, general }

class PredictionsPage extends ConsumerStatefulWidget {
  const PredictionsPage({super.key});

  @override
  ConsumerState<PredictionsPage> createState() => _PredictionsPageState();
}

class _PredictionsPageState extends ConsumerState<PredictionsPage> {
  _RankingType _selected = _RankingType.match;

  @override
  Widget build(BuildContext context) {
    final leaderboardAsync = ref.watch(leaderboardProvider);

    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Classement')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(leaderboardProvider);
          await ref.read(leaderboardProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            SegmentedButton<_RankingType>(
              segments: const [
                ButtonSegment(
                  value: _RankingType.match,
                  label: Text('Matchs'),
                  icon: Icon(Icons.sports_soccer_outlined),
                ),
                ButtonSegment(
                  value: _RankingType.general,
                  label: Text('Général'),
                  icon: Icon(Icons.emoji_events_outlined),
                ),
              ],
              selected: {_selected},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                setState(() => _selected = selection.first);
              },
            ),
            const SizedBox(height: 22),
            Text(
              _selected == _RankingType.match
                  ? 'Classement matchs'
                  : 'Classement général',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              _selected == _RankingType.match
                  ? 'Points gagnés sur les scores des matchs.'
                  : 'Score pondéré : 2/3 matchs, 1/3 saison.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            leaderboardAsync.when(
              loading: () => const Card(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (_, __) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(Icons.cloud_off_outlined, size: 42),
                      const SizedBox(height: 12),
                      const Text(
                        'Le classement est temporairement indisponible.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => ref.invalidate(leaderboardProvider),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (entries) =>
                  _RankingCard(entries: entries, type: _selected),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({required this.entries, required this.type});

  final List<LeaderboardEntry> entries;
  final _RankingType type;

  double _points(LeaderboardEntry entry) =>
      type == _RankingType.match ? entry.matchPoints : entry.totalPoints;

  String _format(double value) {
    if ((value - value.round()).abs() < 0.000001) return '${value.round()}';
    return '${value.ceil()}';
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...entries]
      ..sort((a, b) {
        final points = _points(b).compareTo(_points(a));
        return points != 0 ? points : a.name.compareTo(b.name);
      });

    if (sorted.isEmpty || sorted.every((entry) => _points(entry) == 0)) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Aucun point calculable pour le moment.'),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: sorted.indexed.map((indexed) {
          final rank = indexed.$1 + 1;
          final entry = indexed.$2;
          return Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                leading: CircleAvatar(
                  child: Text(
                    rank <= 3 ? ['🥇', '🥈', '🥉'][rank - 1] : '$rank',
                  ),
                ),
                title: Text(
                  entry.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (type == _RankingType.match) ...[
                      _StatBadge(label: 'Bons paris', value: entry.matchBons),
                      const SizedBox(width: 10),
                      _StatBadge(label: 'Exacts', value: entry.matchExacts),
                      const SizedBox(width: 14),
                    ],
                    Text(
                      '${_format(_points(entry))} pts',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              if (rank < sorted.length) const Divider(height: 1),
            ],
          );
        }).toList(),
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
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: scheme.primary,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
