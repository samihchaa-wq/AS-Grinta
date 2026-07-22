import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/features/badges/presentation/name_with_badges.dart';
import 'package:as_grinta/features/predictions/data/leaderboard_repository.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
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

  double _points(LeaderboardEntry item) {
    return switch (_mode) {
      _LeaderboardMode.cumulative => item.totalPoints,
      _LeaderboardMode.season => item.seasonPoints,
      _LeaderboardMode.match => item.matchPoints,
    };
  }

  @override
  Widget build(BuildContext context) {
    final leaderboardAsync = ref.watch(leaderboardProvider);

    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Classement général')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<_LeaderboardMode>(
              segments: const [
                ButtonSegment(
                  value: _LeaderboardMode.cumulative,
                  label: Text('Général'),
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
          if (_mode == _LeaderboardMode.cumulative)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Total = points matchs + points saison.',
                style: TextStyle(fontSize: 12),
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
                        child: Text(humanizeError(error)),
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
                          child: GrintaEmptyState(
                            icon: Icons.leaderboard_rounded,
                            title: 'Classement à venir',
                            message: 'Le classement se remplit dès les '
                                'premiers pronostics notés.',
                          ),
                        ),
                      ],
                    );
                  }

                  final sorted = [...entries]
                    ..sort((a, b) => _points(b).compareTo(_points(a)));
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: sorted.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = sorted[index];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(child: Text('${index + 1}')),
                          title: NameWithBadges(
                            profileId: item.profileId,
                            name: item.name,
                          ),
                          trailing: Text(
                            _formatNumber(_points(item)),
                            style: Theme.of(context).textTheme.titleMedium,
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
}
