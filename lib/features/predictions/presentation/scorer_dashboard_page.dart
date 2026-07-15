import 'dart:math' as math;

import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:as_grinta/features/predictions/presentation/enhanced_season_predictions_page.dart';
import 'package:as_grinta/features/predictions/presentation/season_prediction_entry_page.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/player_predictions_sheet.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/reference_player_gauge_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ScorerDashboardPage extends ConsumerWidget {
  const ScorerDashboardPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(enhancedSeasonLockedProvider);
    return locked.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (isLocked) {
        if (!isLocked) {
          return SeasonPredictionEntryPage(embedded: embedded);
        }
        return _LockedScorerDashboard(embedded: embedded);
      },
    );
  }
}

class _LockedScorerDashboard extends ConsumerWidget {
  const _LockedScorerDashboard({required this.embedded});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gaugesAsync = ref.watch(enhancedSeasonGaugesProvider);
    final currentUserId =
        ref.read(seasonPredictionsRepositoryProvider).currentUserId;

    return gaugesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (gauges) {
        final scorers = gauges.where((gauge) => !gauge.isGoalkeeper).toList()
          ..sort(_comparePlayers);
        final keepers = gauges.where((gauge) => gauge.isGoalkeeper).toList()
          ..sort(_comparePlayers);

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(enhancedSeasonLockedProvider);
            ref.invalidate(enhancedSeasonGaugesProvider);
            await ref.read(enhancedSeasonGaugesProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (scorers.isNotEmpty)
                _GaugeSection(
                  title: 'Buteurs',
                  icon: Icons.sports_soccer,
                  gauges: scorers,
                  scaleMax: _scale(scorers, 20),
                  currentUserId: currentUserId,
                  onOpen: (gauge) => _openPlayerDetails(
                    context,
                    gauge,
                    currentUserId,
                  ),
                ),
              if (scorers.isNotEmpty && keepers.isNotEmpty)
                const SizedBox(height: 20),
              if (keepers.isNotEmpty)
                _GaugeSection(
                  title: 'Clean sheets',
                  icon: Icons.sports_handball_outlined,
                  gauges: keepers,
                  scaleMax: _scale(keepers, 15),
                  currentUserId: currentUserId,
                  onOpen: (gauge) => _openPlayerDetails(
                    context,
                    gauge,
                    currentUserId,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static int _comparePlayers(PlayerGauge a, PlayerGauge b) {
    final byActual = b.actual.compareTo(a.actual);
    if (byActual != 0) return byActual;
    final byMedian = b.median.compareTo(a.median);
    if (byMedian != 0) return byMedian;
    return a.playerName.toLowerCase().compareTo(b.playerName.toLowerCase());
  }

  static int _scale(List<PlayerGauge> gauges, int fallback) {
    var observed = fallback;
    for (final gauge in gauges) {
      observed = math.max(observed, gauge.maxValue);
    }
    return ((observed + 4) ~/ 5) * 5;
  }

  static Future<void> _openPlayerDetails(
    BuildContext context,
    PlayerGauge gauge,
    String? currentUserId,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: .82,
        minChildSize: .5,
        maxChildSize: .96,
        expand: false,
        builder: (_, controller) => PlayerPredictionsSheet(
          gauge: gauge,
          currentUserId: currentUserId,
          scrollController: controller,
        ),
      ),
    );
  }
}

class _GaugeSection extends StatelessWidget {
  const _GaugeSection({
    required this.title,
    required this.icon,
    required this.gauges,
    required this.scaleMax,
    required this.currentUserId,
    required this.onOpen,
  });

  final String title;
  final IconData icon;
  final List<PlayerGauge> gauges;
  final int scaleMax;
  final String? currentUserId;
  final ValueChanged<PlayerGauge> onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1D3B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF4B6FFF).withValues(alpha: .38),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF4B6FFF).withValues(alpha: .12),
                  border: Border.all(
                    color: const Color(0xFF4B6FFF).withValues(alpha: .36),
                  ),
                ),
                child: Icon(icon, color: const Color(0xFF79A4FF), size: 24),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final gauge in gauges)
            ReferencePlayerGaugeCard(
              gauge: gauge,
              scaleMax: scaleMax,
              personalPrediction: gauge.predictionFor(currentUserId)?.value,
              onTap: () => onOpen(gauge),
            ),
        ],
      ),
    );
  }
}
