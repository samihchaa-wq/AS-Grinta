import 'package:as_grinta/features/predictions/data/leaderboard_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _LeaderboardMode { cumulative, season, match }

class LeaderboardPage extends ConsumerStatefulWidget {
  const LeaderboardPage({super.key});

  @override
  ConsumerState<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends ConsumerState<LeaderboardPage> {
  _LeaderboardMode _mode = _LeaderboardMode.cumulative;

  String _formatNumber(double value) {
    return value == value.truncateToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final leaderboardAsync = ref.watch(leaderboardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Classements pronostics')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<_LeaderboardMode>(
              segments: const [
                ButtonSegment(
                  value: _LeaderboardMode.cumulative,
                  label: Text('Cumulé'),
                ),
                ButtonSegment(
                  value: _LeaderboardMode.season,
                  label: Text('Saison'),
                ),
                ButtonSegment(
                  value: _LeaderboardMode.match,
                  label: Text('Match'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) {
                setState(() => _mode = selection.first);
              },
            ),
          ),
          Expanded(
            child: RefreshIndicator(
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

                  final sorted = [...entries]
                    ..sort((a, b) => _points(b).compareTo(_points(a)));

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: sorted.length,
                    itemBuilder: (context, index) {
                      final item = sorted[index];
                      final points = _points(item);
                      final maxPoints = _maxPoints(item);
                      final percentage =
                          maxPoints <= 0 ? 0.0 : points * 100 / maxPoints;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(child: Text('${index + 1}')),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      item.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                  Text(
                                    _formatNumber(points),
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text('${_formatNumber(percentage)} %'),
                              const SizedBox(height: 4),
                              LinearProgressIndicator(
                                value: (percentage / 100)
                                    .clamp(0.0, 1.0)
                                    .toDouble(),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _points(LeaderboardEntry item) {
    return switch (_mode) {
      _LeaderboardMode.cumulative => item.totalPoints,
      _LeaderboardMode.season => item.seasonPoints,
      _LeaderboardMode.match => item.matchPoints,
    };
  }

  double _maxPoints(LeaderboardEntry item) {
    return switch (_mode) {
      _LeaderboardMode.cumulative => item.totalMaxPoints,
      _LeaderboardMode.season => item.seasonMaxPoints,
      _LeaderboardMode.match => item.matchMaxPoints,
    };
  }
}