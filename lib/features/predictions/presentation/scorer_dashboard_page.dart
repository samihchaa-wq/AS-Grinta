import 'dart:math' as math;

import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:as_grinta/features/predictions/presentation/enhanced_season_predictions_page.dart';
import 'package:as_grinta/features/predictions/presentation/season_predictions_page.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/premium_season_gauges.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
        final scorers =
            players.where((player) => !player.isGoalkeeper).toList();
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
              _PodiumStrip(
                players: scorers.take(3).toList(),
                onOpen: (gauge) => _openPlayerDetails(
                  context,
                  gauge,
                  currentUserId,
                ),
                onOpenRanking: () => context.go('/pronos?category=general'),
              ),
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

class _PodiumStrip extends StatelessWidget {
  const _PodiumStrip({
    required this.players,
    required this.onOpen,
    required this.onOpenRanking,
  });

  final List<PlayerGauge> players;
  final ValueChanged<PlayerGauge> onOpen;
  final VoidCallback onOpenRanking;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF071426),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF425D8C)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            children: [
              for (var index = 0; index < players.length; index++) ...[
                _PodiumPlayer(
                  rank: index + 1,
                  gauge: players[index],
                  onTap: () => onOpen(players[index]),
                ),
                if (index != players.length - 1)
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: .08),
                  ),
              ],
              InkWell(
                onTap: onOpenRanking,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(26)),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'VOIR LE CLASSEMENT',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.chevron_right, color: Colors.white70),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PodiumPlayer extends StatelessWidget {
  const _PodiumPlayer({
    required this.rank,
    required this.gauge,
    required this.onTap,
  });

  final int rank;
  final PlayerGauge gauge;
  final VoidCallback onTap;

  Color get _rankColor => switch (rank) {
        1 => _actualBlue,
        2 => _personalGold,
        _ => _medianPurple,
      };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              child: Text(
                rank.toString().padLeft(2, '0'),
                style: TextStyle(
                  color: _rankColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            _PlayerAvatar(name: gauge.playerName, size: 54),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                gauge.playerName.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            Text(
              '${gauge.actual}',
              style: TextStyle(
                color: _rankColor,
                fontSize: 34,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              gauge.actual == 1 ? 'BUT' : 'BUTS',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 760),
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
        ),
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
      fontSize: 11,
      fontWeight: FontWeight.w800,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: const Row(
        children: [
          SizedBox(width: 250, child: Text('JOUEUR', style: style)),
          SizedBox(
            width: 100,
            child: Text('ACTUEL', style: style, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: 110,
            child: Text('TON PRONO', style: style, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: 100,
            child: Text('MÉDIANE', style: style, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: 150,
            child:
                Text('ÉCART PRONO', style: style, textAlign: TextAlign.center),
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
    final versusActual =
        personalPrediction == null ? null : personalPrediction! - gauge.actual;
    final versusMedian = personalPrediction == null || median == null
        ? null
        : personalPrediction! - median;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 250,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 38,
                          child: Text(
                            rank.toString().padLeft(2, '0'),
                            style: const TextStyle(
                              color: _actualBlue,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        _PlayerAvatar(name: gauge.playerName, size: 64),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                gauge.playerName.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                gauge.isGoalkeeper ? 'GARDIEN' : 'ATTAQUANT',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _MetricCell(
                    width: 100,
                    value: gauge.actual,
                    color: _actualBlue,
                    label: gauge.isGoalkeeper ? 'CLEAN SHEET' : 'BUTS',
                  ),
                  _MetricCell(
                    width: 110,
                    value: personalPrediction,
                    color: _personalGold,
                    label: gauge.isGoalkeeper ? 'CLEAN SHEETS' : 'BUTS',
                  ),
                  _MetricCell(
                    width: 100,
                    value: median,
                    color: _medianPurple,
                    label: gauge.isGoalkeeper ? 'CLEAN SHEETS' : 'BUTS',
                  ),
                  SizedBox(
                    width: 150,
                    child: Column(
                      children: [
                        _DeltaValue(value: versusActual, label: 'vs actuel'),
                        const SizedBox(height: 9),
                        Divider(color: Colors.white.withValues(alpha: .10)),
                        const SizedBox(height: 5),
                        _DeltaValue(value: versusMedian, label: 'vs médiane'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _InsightStrip(
                playerName: gauge.playerName,
                personalPrediction: personalPrediction,
                median: median,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.width,
    required this.value,
    required this.color,
    required this.label,
  });

  final double width;
  final int? value;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .75)),
          color: color.withValues(alpha: .05),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: .10),
              blurRadius: 14,
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              value?.toString() ?? '—',
              style: TextStyle(
                color: color,
                fontSize: 30,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeltaValue extends StatelessWidget {
  const _DeltaValue({required this.value, required this.label});

  final int? value;
  final String label;

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
    return Column(
      children: [
        Text(
          display,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 10)),
      ],
    );
  }
}

class _InsightStrip extends StatelessWidget {
  const _InsightStrip({
    required this.playerName,
    required this.personalPrediction,
    required this.median,
  });

  final String playerName;
  final int? personalPrediction;
  final int? median;

  @override
  Widget build(BuildContext context) {
    final comparison = personalPrediction == null || median == null
        ? null
        : personalPrediction! - median!;
    final color = comparison == null
        ? Colors.white54
        : comparison > 0
            ? _actualBlue
            : comparison < 0
                ? _personalGold
                : _negativeGreen;
    final title = comparison == null
        ? 'Pronostic à compléter.'
        : comparison > 0
            ? 'Tu vois grand pour $playerName !'
            : comparison < 0
                ? 'Prudent sur $playerName.'
                : 'Aligné avec la médiane.';
    final subtitle = comparison == null
        ? 'Renseigne ton estimation pour la comparer.'
        : comparison > 0
            ? 'Tu es au-dessus de la médiane.'
            : comparison < 0
                ? 'Tu pronostiques moins que la majorité.'
                : 'Ton pronostic rejoint celui du groupe.';

    return Container(
      width: 710,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          Icon(Icons.trending_up, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerAvatar extends StatelessWidget {
  const _PlayerAvatar({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF183C72), Color(0xFF0A1831)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _actualBlue.withValues(alpha: .55)),
        boxShadow: [
          BoxShadow(
            color: _actualBlue.withValues(alpha: .18),
            blurRadius: 16,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: math.max(18, size * .34),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
