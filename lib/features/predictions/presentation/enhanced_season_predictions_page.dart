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

enum _SeasonView { players, predictors, ranking }

class EnhancedSeasonPredictionsPage extends ConsumerStatefulWidget {
  const EnhancedSeasonPredictionsPage({super.key});

  @override
  ConsumerState<EnhancedSeasonPredictionsPage> createState() =>
      _EnhancedSeasonPredictionsPageState();
}

class _EnhancedSeasonPredictionsPageState
    extends ConsumerState<EnhancedSeasonPredictionsPage> {
  _SeasonView _view = _SeasonView.players;
  String? _selectedPredictorId;

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(enhancedSeasonLockedProvider);
    return locked.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(body: Center(child: Text('$error'))),
      data: (isLocked) {
        if (!isLocked) return const SeasonPredictionsPage();
        return _lockedPage();
      },
    );
  }

  Widget _lockedPage() {
    final gaugesAsync = ref.watch(enhancedSeasonGaugesProvider);
    final completedMatchesAsync =
        ref.watch(enhancedSeasonCompletedMatchesProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Pronos de saison ✨'),
        backgroundColor: Colors.transparent,
      ),
      body: gaugesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (gauges) {
          final currentUserId = ref
              .read(seasonPredictionsRepositoryProvider)
              .currentUserId;
          final predictors = _predictors(gauges);
          _selectedPredictorId ??=
              predictors.any((item) => item.id == currentUserId)
                  ? currentUserId
                  : predictors.firstOrNull?.id;

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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                Text(
                  '${predictors.length} pronostiqueurs',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                completedMatchesAsync.when(
                  loading: () => const Text(
                    'Nombre de matchs joués : …',
                    style: TextStyle(color: Colors.white60),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (count) => Text(
                    'Nombre de matchs joués : $count',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SegmentedButton<_SeasonView>(
                  segments: const [
                    ButtonSegment(
                      value: _SeasonView.players,
                      icon: Icon(Icons.sports_soccer),
                      label: FittedBox(child: Text('Joueurs')),
                    ),
                    ButtonSegment(
                      value: _SeasonView.predictors,
                      icon: Icon(Icons.group_outlined),
                      label: FittedBox(child: Text('Pronostiqueurs')),
                    ),
                    ButtonSegment(
                      value: _SeasonView.ranking,
                      icon: Icon(Icons.emoji_events_outlined),
                      label: FittedBox(child: Text('Classement')),
                    ),
                  ],
                  selected: {_view},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    setState(() => _view = selection.first);
                  },
                ),
                const SizedBox(height: 22),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: switch (_view) {
                    _SeasonView.players => _playersView(gauges),
                    _SeasonView.predictors =>
                      _predictorsView(gauges, predictors, currentUserId),
                    _SeasonView.ranking => const SeasonRankingPanel(),
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _playersView(List<PlayerGauge> gauges) {
    final scorers = gauges.where((gauge) => !gauge.isGoalkeeper).toList();
    final keepers = gauges.where((gauge) => gauge.isGoalkeeper).toList();
    return Column(
      key: const ValueKey('players'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (scorers.isNotEmpty) ...[
          const _SectionTitle('Buteurs'),
          ...scorers.map(
            (gauge) => PremiumSeasonGaugeCard(
              gauge: gauge,
              scaleMax: _scale(scorers, 20),
              onOpenAll: () {},
              onOpenMedian: () {},
            ),
          ),
          const SizedBox(height: 18),
        ],
        if (keepers.isNotEmpty) ...[
          const _SectionTitle('Gardiens · clean sheets'),
          ...keepers.map(
            (gauge) => PremiumSeasonGaugeCard(
              gauge: gauge,
              scaleMax: _scale(keepers, 15),
              onOpenAll: () {},
              onOpenMedian: () {},
            ),
          ),
        ],
      ],
    );
  }

  Widget _predictorsView(
    List<PlayerGauge> gauges,
    List<({String id, String name})> predictors,
    String? currentUserId,
  ) {
    final selectedId = _selectedPredictorId;
    final selected = predictors.where((item) => item.id == selectedId).toList();
    final selectedName = selected.firstOrNull?.name ?? 'Pronostiqueur';

    int compareByPrediction(PlayerGauge a, PlayerGauge b) {
      final aPrediction = a.predictionFor(selectedId)?.value ?? -1;
      final bPrediction = b.predictionFor(selectedId)?.value ?? -1;
      final byPrediction = bPrediction.compareTo(aPrediction);
      if (byPrediction != 0) return byPrediction;
      final byActual = b.actual.compareTo(a.actual);
      if (byActual != 0) return byActual;
      return a.playerName.toLowerCase().compareTo(b.playerName.toLowerCase());
    }

    final scorers = gauges.where((gauge) => !gauge.isGoalkeeper).toList()
      ..sort(compareByPrediction);
    final keepers = gauges.where((gauge) => gauge.isGoalkeeper).toList()
      ..sort(compareByPrediction);

    return Column(
      key: const ValueKey('predictors'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: selectedId,
          decoration: InputDecoration(
            labelText: 'Consulter les pronostics de',
            prefixIcon: const Icon(Icons.person_search_outlined),
            filled: true,
            fillColor: const Color(0xFF0A1931),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
          items: [
            for (final predictor in predictors)
              DropdownMenuItem(
                value: predictor.id,
                child: Text(
                  predictor.id == currentUserId
                      ? '${predictor.name} (moi)'
                      : predictor.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) => setState(() => _selectedPredictorId = value),
        ),
        const SizedBox(height: 18),
        Text(
          selectedName,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const Text(
          'Barre = score réel · Trait = ton pronostic',
          style: TextStyle(color: Colors.white60),
        ),
        const SizedBox(height: 18),
        if (scorers.isNotEmpty) ...[
          const _SectionTitle('Buteurs'),
          _PredictorProgressList(gauges: scorers, predictorId: selectedId),
          const SizedBox(height: 20),
        ],
        if (keepers.isNotEmpty) ...[
          const _SectionTitle('Gardiens · clean sheets'),
          _PredictorProgressList(gauges: keepers, predictorId: selectedId),
        ],
      ],
    );
  }

  int _scale(List<PlayerGauge> gauges, int fallback) {
    var observed = fallback;
    for (final gauge in gauges) {
      observed = math.max(observed, gauge.maxValue);
    }
    return ((observed + 4) ~/ 5) * 5;
  }

  List<({String id, String name})> _predictors(List<PlayerGauge> gauges) {
    final byId = <String, String>{};
    for (final gauge in gauges) {
      for (final prediction in gauge.predictions) {
        byId[prediction.predictorId] = prediction.predictorName;
      }
    }
    return byId.entries
        .map((entry) => (id: entry.key, name: entry.value))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _PredictorProgressList extends StatelessWidget {
  const _PredictorProgressList({
    required this.gauges,
    required this.predictorId,
  });

  final List<PlayerGauge> gauges;
  final String? predictorId;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF08162C),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < gauges.length; index++) ...[
            _PredictorProgressRow(
              gauge: gauges[index],
              prediction: gauges[index].predictionFor(predictorId),
            ),
            if (index != gauges.length - 1)
              Divider(height: 1, color: Colors.white.withValues(alpha: .08)),
          ],
        ],
      ),
    );
  }
}

class _PredictorProgressRow extends StatelessWidget {
  const _PredictorProgressRow({
    required this.gauge,
    required this.prediction,
  });

  final PlayerGauge gauge;
  final GaugePrediction? prediction;

  @override
  Widget build(BuildContext context) {
    final accent = gaugeAccentFor(gauge.playerId);
    final predicted = prediction?.value;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(
              gauge.playerName,
              maxLines: 2,
              softWrap: true,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ActualAgainstPredictionGauge(
              actual: gauge.actual,
              predicted: predicted,
              accent: accent,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 54,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const FittedBox(
                  child: Text(
                    'PRONO',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  predicted?.toString() ?? '—',
                  style: TextStyle(
                    color: accent,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActualAgainstPredictionGauge extends StatelessWidget {
  const _ActualAgainstPredictionGauge({
    required this.actual,
    required this.predicted,
    required this.accent,
  });

  final int actual;
  final int? predicted;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (predicted == null) {
      return const Text('Aucun prono', style: TextStyle(color: Colors.white54));
    }

    final predictionValue = predicted!;
    final baseMax = math.max(1, math.max(actual, predictionValue));
    final visualMax = actual > predictionValue
        ? math.max(baseMax * 1.18, actual + 0.2).toDouble()
        : baseMax.toDouble();
    final actualRatio = (actual / visualMax).clamp(0.0, 1.0).toDouble();
    final predictionRatio =
        (predictionValue / visualMax).clamp(0.0, 1.0).toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final markerX = constraints.maxWidth * predictionRatio;
        return SizedBox(
          height: 38,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              FractionallySizedBox(
                widthFactor: actualRatio,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accent.withValues(alpha: .72), accent],
                    ),
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: .35),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: (markerX - 1.5).clamp(0.0, constraints.maxWidth - 3),
                top: 4,
                child: Container(
                  width: 3,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 5),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 6,
                top: 0,
                child: Text(
                  'Actuel $actual',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
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

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
