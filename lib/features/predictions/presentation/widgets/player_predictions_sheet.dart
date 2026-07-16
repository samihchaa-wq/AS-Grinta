import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/features/badges/presentation/name_with_badges.dart';
import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/premium_season_gauges.dart';
import 'package:flutter/material.dart';

class PlayerPredictionsSheet extends StatelessWidget {
  const PlayerPredictionsSheet({
    super.key,
    required this.gauge,
    required this.currentUserId,
    required this.scrollController,
  });

  final PlayerGauge gauge;
  final String? currentUserId;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final accent = gaugeAccentFor(gauge.playerId);
    final median = gauge.predictions.isEmpty ? null : gauge.median.round();
    final predictions = [...gauge.predictions]..sort((a, b) {
        final aDistance = (a.value - gauge.actual).abs();
        final bDistance = (b.value - gauge.actual).abs();
        final byDistance = aDistance.compareTo(bDistance);
        if (byDistance != 0) return byDistance;

        final byValue = a.value.compareTo(b.value);
        if (byValue != 0) return byValue;
        return a.predictorName.toLowerCase().compareTo(
              b.predictorName.toLowerCase(),
            );
      });

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF061226),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: ListView(
        controller: scrollController,
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gauge.playerName,
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
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
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (median != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFA33CFF).withValues(alpha: .14),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFA33CFF).withValues(alpha: .5),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timeline,
                      color: Color(0xFFC58BFF), size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Médiane des pronos',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    '$median',
                    style: const TextStyle(
                      color: Color(0xFFC58BFF),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          if (median != null) const SizedBox(height: 16),
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
                    rank: _rankFor(predictions, index, gauge.actual),
                    isMine: predictions[index].predictorId == currentUserId,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _rankFor(
    List<GaugePrediction> predictions,
    int index,
    int actual,
  ) {
    if (index == 0) return 1;
    final currentDistance = (predictions[index].value - actual).abs();
    final previousDistance = (predictions[index - 1].value - actual).abs();
    if (currentDistance == previousDistance) {
      return _rankFor(predictions, index - 1, actual);
    }
    return index + 1;
  }
}

class _PredictionRow extends StatelessWidget {
  const _PredictionRow({
    required this.prediction,
    required this.rank,
    required this.isMine,
  });

  final GaugePrediction prediction;
  final int rank;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    const mine = Color(0xFF39E784);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isMine ? mine.withValues(alpha: .12) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: isMine ? Border.all(color: mine.withValues(alpha: .18)) : null,
      ),
      child: Row(
        children: [
          SizedBox(width: 34, child: _RankBadge(rank: rank)),
          const SizedBox(width: 6),
          Expanded(
            child: NameWithBadges(
              profileId: prediction.predictorId,
              name: isMine
                  ? '${prediction.predictorName} (moi)'
                  : prediction.predictorName,
              style: TextStyle(
                color: isMine ? mine : Colors.white,
                fontWeight: isMine ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${prediction.value}',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: isMine ? mine : Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
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
