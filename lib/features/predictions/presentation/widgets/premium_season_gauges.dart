import 'dart:math' as math;

import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:flutter/material.dart';

const _violet = Color(0xFF7C3CFF);
const _pink = Color(0xFFFF4FCB);
const _cyan = Color(0xFF1DCBFF);
const _green = Color(0xFF39E784);
const _amber = Color(0xFFFFBE3D);
const _orange = Color(0xFFFF6A26);

Color gaugeAccentFor(String key) {
  const colors = [_violet, _cyan, _green, _amber, _orange, _pink];
  return colors[key.hashCode.abs() % colors.length];
}

class PremiumSeasonGaugeCard extends StatelessWidget {
  const PremiumSeasonGaugeCard({
    super.key,
    required this.gauge,
    required this.scaleMax,
    required this.onOpenAll,
    required this.onOpenPopular,
  });

  final PlayerGauge gauge;
  final int scaleMax;
  final VoidCallback onOpenAll;
  final ValueChanged<GaugeMarker> onOpenPopular;

  @override
  Widget build(BuildContext context) {
    final accent = gaugeAccentFor(gauge.playerId);
    final popular = _popularMarker(gauge.markers);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF08162C),
        border: Border.all(color: accent.withValues(alpha: .28)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: .12),
            blurRadius: 26,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpenAll,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
            child: Row(
              children: [
                _PlayerAvatar(name: gauge.playerName, accent: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gauge.playerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.3,
                            ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        gauge.isGoalkeeper
                            ? AppFormats.counted(
                                gauge.actual,
                                'clean sheet actuel',
                                'clean sheets actuels',
                              )
                            : AppFormats.counted(
                                gauge.actual,
                                'but actuel',
                                'buts actuels',
                              ),
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 11),
                      PremiumGaugeLine(
                        actual: gauge.actual,
                        maxValue: scaleMax,
                        popular: popular,
                        accent: accent,
                        onPopularTap: popular == null
                            ? null
                            : () => onOpenPopular(popular),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _OpenButton(
                  count: gauge.predictions.length,
                  accent: accent,
                  onTap: onOpenAll,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  GaugeMarker? _popularMarker(List<GaugeMarker> markers) {
    if (markers.isEmpty) return null;
    final sorted = [...markers]
      ..sort((a, b) {
        final count = b.predictions.length.compareTo(a.predictions.length);
        if (count != 0) return count;
        return b.value.compareTo(a.value);
      });
    return sorted.first;
  }
}

class PremiumGaugeLine extends StatelessWidget {
  const PremiumGaugeLine({
    super.key,
    required this.actual,
    required this.maxValue,
    required this.popular,
    required this.accent,
    required this.onPopularTap,
  });

  final int actual;
  final int maxValue;
  final GaugeMarker? popular;
  final Color accent;
  final VoidCallback? onPopularTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const markerRadius = 16.0;
        final usable = math.max(1.0, constraints.maxWidth - markerRadius * 2);
        double xFor(num value) {
          final ratio = (value / math.max(1, maxValue)).clamp(0.0, 1.0);
          return markerRadius + usable * ratio;
        }

        return SizedBox(
          height: 54,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: markerRadius,
                right: markerRadius,
                top: 22,
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    gradient: LinearGradient(
                      colors: [
                        accent.withValues(alpha: .72),
                        accent,
                        _pink,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: .3),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: xFor(actual) - markerRadius,
                top: 4,
                child: _CurrentBall(value: actual, accent: accent),
              ),
              if (popular != null && popular!.value != actual)
                Positioned(
                  left: xFor(popular!.value) - markerRadius,
                  top: 2,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onPopularTap,
                    child: _PopularBubble(
                      value: popular!.value,
                      accent: accent,
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                bottom: 0,
                child: Text(
                  '0',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white70,
                      ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Text(
                  '$maxValue',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white70,
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlayerAvatar extends StatelessWidget {
  const _PlayerAvatar({required this.name, required this.accent});

  final String name;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0C1D38),
        border: Border.all(color: accent, width: 1.8),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: .34),
            blurRadius: 16,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w900,
          shadows: [Shadow(color: accent, blurRadius: 14)],
        ),
      ),
    );
  }
}

class _CurrentBall extends StatelessWidget {
  const _CurrentBall({required this.value, required this.accent});

  final int value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [BoxShadow(color: accent, blurRadius: 12)],
          ),
          child: Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 1),
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFF8FAFF),
            border: Border.all(color: accent, width: 2.4),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: .7),
                blurRadius: 14,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(Icons.sports_soccer, color: Color(0xFF09152A), size: 23),
        ),
      ],
    );
  }
}

class _PopularBubble extends StatelessWidget {
  const _PopularBubble({required this.value, required this.accent});

  final int value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF111B35),
        border: Border.all(color: _pink, width: 1.7),
        boxShadow: [
          BoxShadow(color: _pink.withValues(alpha: .75), blurRadius: 18),
          BoxShadow(color: accent.withValues(alpha: .35), blurRadius: 28),
        ],
      ),
      child: Text(
        '$value',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _OpenButton extends StatelessWidget {
  const _OpenButton({
    required this.count,
    required this.accent,
    required this.onTap,
  });

  final int count;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: accent.withValues(alpha: .34)),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Voir les $count',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    );
  }
}

class PremiumPlayerDetailsSheet extends StatefulWidget {
  const PremiumPlayerDetailsSheet({
    super.key,
    required this.gauge,
    required this.currentUserId,
    required this.scrollController,
  });

  final PlayerGauge gauge;
  final String? currentUserId;
  final ScrollController scrollController;

  @override
  State<PremiumPlayerDetailsSheet> createState() =>
      _PremiumPlayerDetailsSheetState();
}

class _PremiumPlayerDetailsSheetState extends State<PremiumPlayerDetailsSheet> {
  bool _sortByScore = true;

  @override
  Widget build(BuildContext context) {
    final gauge = widget.gauge;
    final accent = gaugeAccentFor(gauge.playerId);
    final predictions = [...gauge.predictions];
    if (_sortByScore) {
      predictions.sort((a, b) {
        final value = b.value.compareTo(a.value);
        return value != 0
            ? value
            : a.predictorName.toLowerCase().compareTo(b.predictorName.toLowerCase());
      });
    } else {
      predictions.sort((a, b) =>
          a.predictorName.toLowerCase().compareTo(b.predictorName.toLowerCase()));
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF061226),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
        children: [
          Center(
            child: Container(
              width: 46,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
              const SizedBox(width: 12),
              _PlayerAvatar(name: gauge.playerName, accent: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gauge.playerName,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    Text(
                      gauge.isGoalkeeper
                          ? AppFormats.counted(
                              gauge.actual,
                              'clean sheet actuel',
                              'clean sheets actuels',
                            )
                          : AppFormats.counted(
                              gauge.actual,
                              'but actuel',
                              'buts actuels',
                            ),
                      style: TextStyle(color: accent, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'Tous les pronostics (${predictions.length})',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .035),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: .06)),
            ),
            child: Row(
              children: [
                Expanded(child: _SortButton(
                  selected: _sortByScore,
                  label: 'Trier par score',
                  accent: accent,
                  onTap: () => setState(() => _sortByScore = true),
                )),
                Expanded(child: _SortButton(
                  selected: !_sortByScore,
                  label: 'Trier par nom',
                  accent: accent,
                  onTap: () => setState(() => _sortByScore = false),
                )),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0B1932),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: accent.withValues(alpha: .22)),
            ),
            child: Column(
              children: [
                for (var index = 0; index < predictions.length; index++)
                  _PredictionRow(
                    prediction: predictions[index],
                    rank: _sortByScore ? _rankFor(predictions, index) : index + 1,
                    maxValue: math.max(1, gauge.maximum),
                    isMine: predictions[index].predictorId == widget.currentUserId,
                    accent: accent,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _rankFor(List<GaugePrediction> predictions, int index) {
    if (index == 0) return 1;
    if (predictions[index].value == predictions[index - 1].value) {
      return _rankFor(predictions, index - 1);
    }
    return index + 1;
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({
    required this.selected,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: .23) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white60,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PredictionRow extends StatelessWidget {
  const _PredictionRow({
    required this.prediction,
    required this.rank,
    required this.maxValue,
    required this.isMine,
    required this.accent,
  });

  final GaugePrediction prediction;
  final int rank;
  final int maxValue;
  final bool isMine;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final progress = (prediction.value / maxValue).clamp(0.0, 1.0).toDouble();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isMine ? _green.withValues(alpha: .12) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: isMine ? Border.all(color: _green.withValues(alpha: .18)) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: _RankBadge(rank: rank),
          ),
          CircleAvatar(
            radius: 16,
            backgroundColor: accent.withValues(alpha: .18),
            child: Text(
              prediction.predictorName.trim().isEmpty
                  ? '?'
                  : prediction.predictorName.trim()[0].toUpperCase(),
              style: TextStyle(
                color: isMine ? _green : Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Text(
              isMine
                  ? '${prediction.predictorName} (moi)'
                  : prediction.predictorName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isMine ? _green : Colors.white,
                fontWeight: isMine ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: .06),
                color: isMine ? _green : accent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 30,
            child: Text(
              '${prediction.value}',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: isMine ? _green : Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final color = switch (rank) {
      1 => const Color(0xFFFFC43D),
      2 => const Color(0xFFD7E0EE),
      3 => const Color(0xFFFF925D),
      _ => Colors.transparent,
    };
    if (rank > 3) {
      return Text(
        '$rank',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white60),
      );
    }
    return CircleAvatar(
      radius: 13,
      backgroundColor: color,
      child: Text(
        '$rank',
        style: const TextStyle(
          color: Color(0xFF071326),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
