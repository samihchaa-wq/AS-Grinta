import 'dart:math' as math;

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:as_grinta/features/predictions/presentation/season_predictions_page.dart';
import 'package:as_grinta/features/predictions/presentation/season_ranking_panel.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/premium_season_gauges.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final enhancedSeasonLockedProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(seasonPredictionsRepositoryProvider).isLocked();
});

final enhancedSeasonGaugesProvider =
    FutureProvider.autoDispose<List<PlayerGauge>>((ref) {
  return ref.watch(seasonPredictionsRepositoryProvider).fetchGauges();
});

final enhancedSeasonCompletedMatchesProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final season = await client
      .from('seasons')
      .select('id')
      .eq('status', 'open')
      .maybeSingle();
  final seasonId = season?['id']?.toString();
  if (seasonId == null) return 0;

  final rows = await client
      .from('matches')
      .select('id')
      .eq('season_id', seasonId)
      .inFilter('status', const ['termine', 'archive']);
  return (rows as List).length;
});

enum _SeasonView { players, ranking }

class EnhancedSeasonPredictionsPage extends ConsumerStatefulWidget {
  const EnhancedSeasonPredictionsPage({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  @override
  ConsumerState<EnhancedSeasonPredictionsPage> createState() =>
      _EnhancedSeasonPredictionsPageState();
}

class _EnhancedSeasonPredictionsPageState
    extends ConsumerState<EnhancedSeasonPredictionsPage> {
  _SeasonView _view = _SeasonView.players;

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(enhancedSeasonLockedProvider);
    return locked.when(
      loading: () => const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: Text('$error')),
      ),
      data: (isLocked) {
        if (!isLocked) return const SeasonPredictionsPage();
        return _lockedPage();
      },
    );
  }

  Widget _lockedPage() {
    final gaugesAsync = ref.watch(enhancedSeasonGaugesProvider);
    final completedMatches = ref.watch(enhancedSeasonCompletedMatchesProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Pronos de saison ✨'),
              backgroundColor: Colors.transparent,
            ),
      body: gaugesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (gauges) {
          final currentUserId =
              ref.read(seasonPredictionsRepositoryProvider).currentUserId;

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(enhancedSeasonLockedProvider);
              ref.invalidate(enhancedSeasonGaugesProvider);
              ref.invalidate(enhancedSeasonCompletedMatchesProvider);
              await Future.wait([
                ref.read(enhancedSeasonGaugesProvider.future),
                ref.read(enhancedSeasonCompletedMatchesProvider.future),
              ]);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              children: [
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<_SeasonView>(
                    segments: const [
                      ButtonSegment(
                        value: _SeasonView.players,
                        icon: Icon(Icons.sports_soccer),
                        label: Text('Par joueur'),
                      ),
                      ButtonSegment(
                        value: _SeasonView.ranking,
                        icon: Icon(Icons.emoji_events_outlined),
                        label: Text('Classement'),
                      ),
                    ],
                    selected: {_view},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      setState(() => _view = selection.first);
                    },
                  ),
                ),
                const SizedBox(height: 14),
                if (_view == _SeasonView.players) ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: completedMatches.when(
                      loading: () => const Text(
                        'Matchs joués : …',
                        style: TextStyle(color: Colors.white60),
                      ),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (count) => Text(
                        'Matchs joués : $count',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _GaugeLegend(),
                  const SizedBox(height: 16),
                  _playersView(context, gauges, currentUserId),
                ] else
                  const SeasonRankingPanel(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _playersView(
    BuildContext context,
    List<PlayerGauge> gauges,
    String? currentUserId,
  ) {
    int compareByActualThenMedian(PlayerGauge a, PlayerGauge b) {
      final byActual = b.actual.compareTo(a.actual);
      if (byActual != 0) return byActual;
      final byMedian = b.median.compareTo(a.median);
      if (byMedian != 0) return byMedian;
      return a.playerName.toLowerCase().compareTo(b.playerName.toLowerCase());
    }

    final scorers = gauges.where((gauge) => !gauge.isGoalkeeper).toList()
      ..sort(compareByActualThenMedian);
    final keepers = gauges.where((gauge) => gauge.isGoalkeeper).toList()
      ..sort(compareByActualThenMedian);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (scorers.isNotEmpty) ...[
          _SeasonGroupPanel(
            title: 'Buteurs',
            icon: Icons.sports_soccer,
            children: scorers
                .map(
                  (gauge) => PremiumSeasonGaugeCard(
                    gauge: gauge,
                    scaleMax: _scale(scorers, 20),
                    personalPrediction:
                        gauge.predictionFor(currentUserId)?.value,
                    onOpenAll: () =>
                        _openPlayerDetails(context, gauge, currentUserId),
                    onOpenMedian: () =>
                        _openPlayerDetails(context, gauge, currentUserId),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
        ],
        if (keepers.isNotEmpty)
          _SeasonGroupPanel(
            title: 'Gardien · clean sheets',
            icon: Icons.sports_handball_outlined,
            children: keepers
                .map(
                  (gauge) => PremiumSeasonGaugeCard(
                    gauge: gauge,
                    scaleMax: _scale(keepers, 15),
                    personalPrediction:
                        gauge.predictionFor(currentUserId)?.value,
                    onOpenAll: () =>
                        _openPlayerDetails(context, gauge, currentUserId),
                    onOpenMedian: () =>
                        _openPlayerDetails(context, gauge, currentUserId),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  Future<void> _openPlayerDetails(
    BuildContext context,
    PlayerGauge gauge,
    String? currentUserId,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: .78,
        minChildSize: .5,
        maxChildSize: .94,
        expand: false,
        builder: (_, controller) => PremiumPlayerDetailsSheet(
          gauge: gauge,
          currentUserId: currentUserId,
          scrollController: controller,
        ),
      ),
    );
  }

  int _scale(List<PlayerGauge> gauges, int fallback) {
    var observed = fallback;
    for (final gauge in gauges) {
      observed = math.max(observed, gauge.maxValue);
    }
    return ((observed + 4) ~/ 5) * 5;
  }
}

class _SeasonGroupPanel extends StatelessWidget {
  const _SeasonGroupPanel({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1D3B),
        borderRadius: BorderRadius.circular(24),
        border:
            Border.all(color: const Color(0xFF4B6FFF).withValues(alpha: .38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF79A4FF)),
              const SizedBox(width: 10),
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _GaugeLegend extends StatelessWidget {
  const _GaugeLegend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: const [
        _LegendItem(
          icon: Icons.circle,
          label: 'Actuel',
          color: Color(0xFF4B6FFF),
        ),
        _LegendItem(
          icon: Icons.circle,
          label: 'Ton prono',
          color: Color(0xFFFFBE3D),
        ),
        _LegendItem(
          icon: Icons.circle,
          label: 'Médiane',
          color: Color(0xFF9B6CFF),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
