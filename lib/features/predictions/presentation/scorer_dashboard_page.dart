import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:as_grinta/features/predictions/presentation/enhanced_season_predictions_page.dart';
import 'package:as_grinta/features/predictions/presentation/season_predictions_page.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/premium_season_gauges.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _actualBlue = Color(0xFF4285FF);
const _personalGold = Color(0xFFFFBE3D);
const _medianPurple = Color(0xFF9B5CFF);
const _positivePink = Color(0xFFFF4F9A);
const _negativeGreen = Color(0xFF55D477);

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
        if (!isLocked) return const SeasonPredictionsPage();
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
    final completedMatches = ref.watch(enhancedSeasonCompletedMatchesProvider);
    final currentUserId =
        ref.read(seasonPredictionsRepositoryProvider).currentUserId;

    return gaugesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (gauges) {
        final players = [...gauges]..sort(_comparePlayers);
        final matchesCount = completedMatches.valueOrNull ?? 0;

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
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _ScorerHero(matchesCount: matchesCount),
              const SizedBox(height: 18),
              _PlayersTable(
                players: players,
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
    final byCategory =
        (a.isGoalkeeper ? 1 : 0).compareTo(b.isGoalkeeper ? 1 : 0);
    if (byCategory != 0) return byCategory;
    final byActual = b.actual.compareTo(a.actual);
    if (byActual != 0) return byActual;
    return a.playerName.toLowerCase().compareTo(b.playerName.toLowerCase());
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
        initialChildSize: .82,
        minChildSize: .5,
        maxChildSize: .96,
        expand: false,
        builder: (_, controller) => PremiumPlayerDetailsSheet(
          gauge: gauge,
          currentUserId: currentUserId,
          scrollController: controller,
        ),
      ),
    );
  }
}

class _ScorerHero extends StatelessWidget {
  const _ScorerHero({required this.matchesCount});

  final int matchesCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 230,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF050C1C), Color(0xFF111437)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -24,
            top: -32,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFF4FCB).withValues(alpha: .32),
                    const Color(0xFF7C3CFF).withValues(alpha: .08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          const Positioned(
            right: 34,
            top: 24,
            child: Icon(
              Icons.sports_soccer,
              size: 112,
              color: Color(0xFFB86CFF),
              shadows: [
                Shadow(color: Color(0xFFFF4FCB), blurRadius: 34),
                Shadow(color: Color(0xFF4B6FFF), blurRadius: 18),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BUTEURS',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 280,
                  child: Text(
                    'Compare tes pronos, la médiane et les buts après '
                    '$matchesCount matchs.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white70,
                          height: 1.45,
                        ),
                  ),
                ),
                const Spacer(),
                const Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _LegendChip(label: 'Actuel', color: _actualBlue),
                    _LegendChip(label: 'Ton prono', color: _personalGold),
                    _LegendChip(label: 'Médiane', color: _medianPurple),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0C172B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color, blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _PlayersTable extends StatelessWidget {
  const _PlayersTable({
    required this.players,
    required this.currentUserId,
    required this.onOpen,
  });

  final List<PlayerGauge> players;
  final String? currentUserId;
  final ValueChanged<PlayerGauge> onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF071426),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF425D8C)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const _PlayersTableHeader(),
          for (var index = 0; index < players.length; index++)
            _PlayerTableRow(
              rank: index + 1,
              gauge: players[index],
              personalPrediction:
                  players[index].predictionFor(currentUserId)?.value,
              onTap: () => onOpen(players[index]),
            ),
        ],
      ),
    );
  }
}

class _PlayersTableHeader extends StatelessWidget {
  const _PlayersTableHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: Colors.white60,
      fontSize: 9,
      fontWeight: FontWeight.w800,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 4, child: Text('JOUEUR', style: style)),
          Expanded(
            flex: 2,
            child: Text('ACTUEL', style: style, textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 2,
            child: Text('PRONO', style: style, textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 2,
            child: Text('MÉDIANE', style: style, textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 2,
            child: Text('ÉCART', style: style, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

class _PlayerTableRow extends StatelessWidget {
  const _PlayerTableRow({
    required this.rank,
    required this.gauge,
    required this.personalPrediction,
    required this.onTap,
  });

  final int rank;
  final PlayerGauge gauge;
  final int? personalPrediction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final median = gauge.predictions.isEmpty ? null : gauge.median.round();
    final difference = personalPrediction == null || median == null
        ? null
        : personalPrediction! - median;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text(
                        rank.toString().padLeft(2, '0'),
                        style: const TextStyle(
                          color: _actualBlue,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        gauge.playerName.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _CompactValue(value: gauge.actual, color: _actualBlue),
              _CompactValue(value: personalPrediction, color: _personalGold),
              _CompactValue(value: median, color: _medianPurple),
              _CompactDelta(value: difference),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactValue extends StatelessWidget {
  const _CompactValue({required this.value, required this.color});

  final int? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: 2,
      child: Text(
        value?.toString() ?? '—',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _CompactDelta extends StatelessWidget {
  const _CompactDelta({required this.value});

  final int? value;

  @override
  Widget build(BuildContext context) {
    final color = value == null
        ? Colors.white54
        : value! > 0
            ? _positivePink
            : value! < 0
                ? _negativeGreen
                : Colors.white70;
    final display = value == null
        ? '—'
        : value! > 0
            ? '+$value'
            : '$value';

    return Expanded(
      flex: 2,
      child: Text(
        display,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
