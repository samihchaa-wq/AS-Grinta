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
    final completedMatches = ref.watch(enhancedSeasonCompletedMatchesProvider);

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
                completedMatches.when(
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
                switch (_view) {
                  _SeasonView.players =>
                    _playersView(context, gauges, currentUserId),
                  _SeasonView.predictors =>
                    _predictorsView(gauges, predictors, currentUserId),
                  _SeasonView.ranking => const SeasonRankingPanel(),
                },
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
    final scorers = gauges.where((gauge) => !gauge.isGoalkeeper).toList();
    final keepers = gauges.where((gauge) => gauge.isGoalkeeper).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (scorers.isNotEmpty) ...[
          const _SectionTitle('Buteurs'),
          ...scorers.map(
            (gauge) => PremiumSeasonGaugeCard(
              gauge: gauge,
              scaleMax: _scale(scorers, 20),
              onOpenAll: () =>
                  _openPlayerDetails(context, gauge, currentUserId),
              onOpenMedian: () =>
                  _openPlayerDetails(context, gauge, currentUserId),
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
              onOpenAll: () =>
                  _openPlayerDetails(context, gauge, currentUserId),
              onOpenMedian: () =>
                  _openPlayerDetails(context, gauge, currentUserId),
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
    final selectedName = predictors
            .where((item) => item.id == selectedId)
            .firstOrNull
            ?.name ??
        'Pronostiqueur';

    int compare(PlayerGauge a, PlayerGauge b) {
      final aValue = a.predictionFor(selectedId)?.value ?? -1;
      final bValue = b.predictionFor(selectedId)?.value ?? -1;
      final byPrediction = bValue.compareTo(aValue);
      if (byPrediction != 0) return byPrediction;
      final byActual = b.actual.compareTo(a.actual);
      if (byActual != 0) return byActual;
      return a.playerName.toLowerCase().compareTo(b.playerName.toLowerCase());
    }

    final scorers = gauges.where((gauge) => !gauge.isGoalkeeper).toList()
      ..sort(compare);
    final keepers = gauges.where((gauge) => gauge.isGoalkeeper).toList()
      ..sort(compare);

    return Column(
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
          _PredictorList(gauges: scorers, predictorId: selectedId),
          const SizedBox(height: 20),
        ],
        if (keepers.isNotEmpty) ...[
          const _SectionTitle('Gardiens · clean sheets'),
          _PredictorList(gauges: keepers, predictorId: selectedId),
        ],
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

class _PredictorList extends StatelessWidget {
  const _PredictorList({required this.gauges, required this.predictorId});

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
            _PredictorRow(
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

class _PredictorRow extends StatelessWidget {
  const _PredictorRow({required this.gauge, required this.prediction});

  final PlayerGauge gauge;
  final GaugePrediction? prediction;

  @override
  Widget build(BuildContext context) {
    final predicted = prediction?.value;
    final accent = gaugeAccentFor(gauge.playerId);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(
              gauge.playerName,
              maxLines: 2,
              style: const TextStyle(fontWeight: FontWeight.w800, height: 1.05),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ActualPredictionGauge(
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
                const Text(
                  'PRONO',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
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

class _ActualPredictionGauge extends StatelessWidget {
  const _ActualPredictionGauge({
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

    final visualMax = math.max(1, math.max(actual, predicted!)).toDouble();
    final actualRatio = (actual / visualMax).clamp(0.0, 1.0).toDouble();
    final predictionRatio = (predicted! / visualMax).clamp(0.0, 1.0).toDouble();

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
                    color: accent,
                    borderRadius: BorderRadius.circular(99),
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

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
