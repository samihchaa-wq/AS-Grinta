import 'dart:math' as math;

import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final seasonPredictionsProvider =
    FutureProvider.autoDispose<List<SeasonPredictionItem>>((ref) {
  return ref.watch(seasonPredictionsRepositoryProvider).fetchMine();
});

final seasonGaugesProvider =
    FutureProvider.autoDispose<List<PlayerGauge>>((ref) {
  return ref.watch(seasonPredictionsRepositoryProvider).fetchGauges();
});

final seasonPredictionsLockedProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(seasonPredictionsRepositoryProvider).isLocked();
});

enum _GaugeView { players, predictors }

class SeasonPredictionsPage extends ConsumerStatefulWidget {
  const SeasonPredictionsPage({super.key});

  @override
  ConsumerState<SeasonPredictionsPage> createState() =>
      _SeasonPredictionsPageState();
}

class _SeasonPredictionsPageState extends ConsumerState<SeasonPredictionsPage> {
  final Map<String, int> _draftValues = {};
  String? _error;
  bool _isSavingAll = false;
  _GaugeView _gaugeView = _GaugeView.players;
  String? _selectedPredictorId;

  @override
  Widget build(BuildContext context) {
    final locked =
        ref.watch(seasonPredictionsLockedProvider).valueOrNull ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(locked ? 'Pronos de saison' : 'Mes pronos de saison'),
      ),
      body: locked
          ? _buildGauges(ref.watch(seasonGaugesProvider))
          : _buildMine(ref.watch(seasonPredictionsProvider)),
    );
  }

  Widget _buildMine(AsyncValue<List<SeasonPredictionItem>> asyncItems) {
    return asyncItems.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [Text(humanizeError(error))],
      ),
      data: (items) {
        if (items.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: const [
              Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Aucune saison ouverte ou aucun joueur actif dans '
                    'l’effectif.',
                  ),
                ),
              ),
            ],
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            _draftValues.clear();
            ref.invalidate(seasonPredictionsLockedProvider);
            ref.invalidate(seasonPredictionsProvider);
            await ref.read(seasonPredictionsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              ...items.map(_buildPlayerRow),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSavingAll ? null : () => _saveAll(items),
                  icon: _isSavingAll
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(
                    _isSavingAll
                        ? 'Enregistrement...'
                        : 'Valider mes pronostics',
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlayerRow(SeasonPredictionItem item) {
    final key = '${item.playerId}:${item.category}';
    final value = _draftValues[key] ?? item.value;
    final label = item.category == 'clean_sheets' ? 'clean sheets' : 'buts';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                item.playerName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            SizedBox(
              width: 72,
              child: TextFormField(
                key: ValueKey('$key:$value'),
                initialValue: value.toString(),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '0',
                  border: OutlineInputBorder(),
                ),
                onChanged: (raw) {
                  _draftValues[key] = int.tryParse(raw) ?? 0;
                },
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 76,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGauges(AsyncValue<List<PlayerGauge>> asyncGauges) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(seasonGaugesProvider);
        await ref.read(seasonGaugesProvider.future);
      },
      child: asyncGauges.when(
        loading: () => ListView(
          children: const [
            SizedBox(height: 220),
            Center(child: CircularProgressIndicator()),
          ],
        ),
        error: (error, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [Text(humanizeError(error))],
        ),
        data: (gauges) {
          if (gauges.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Aucun joueur dans l’effectif.'),
                  ),
                ),
              ],
            );
          }

          final currentUserId =
              ref.read(seasonPredictionsRepositoryProvider).currentUserId;
          final predictors = _predictorsFrom(gauges);
          if (_selectedPredictorId == null && predictors.isNotEmpty) {
            final hasCurrentUser = currentUserId != null &&
                predictors.any((entry) => entry.id == currentUserId);
            _selectedPredictorId =
                hasCurrentUser ? currentUserId : predictors.first.id;
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              Text(
                '${predictors.length} pronostiqueurs',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 14),
              SegmentedButton<_GaugeView>(
                segments: const [
                  ButtonSegment(
                    value: _GaugeView.players,
                    icon: Icon(Icons.sports_soccer),
                    label: Text('Par joueur'),
                  ),
                  ButtonSegment(
                    value: _GaugeView.predictors,
                    icon: Icon(Icons.person_search_outlined),
                    label: Text('Par pronostiqueur'),
                  ),
                ],
                selected: {_gaugeView},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  setState(() => _gaugeView = selection.first);
                },
              ),
              const SizedBox(height: 20),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _gaugeView == _GaugeView.players
                    ? _playersView(gauges, currentUserId)
                    : _predictorView(
                        gauges,
                        predictors,
                        currentUserId,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _playersView(List<PlayerGauge> gauges, String? currentUserId) {
    final scorers = gauges.where((gauge) => !gauge.isGoalkeeper).toList();
    final keepers = gauges.where((gauge) => gauge.isGoalkeeper).toList();
    final scorerScale = _sectionScale(scorers, defaultMax: 20);
    final keeperScale = _sectionScale(keepers, defaultMax: 15);

    return Column(
      key: const ValueKey('players'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (scorers.isNotEmpty) ...[
          _sectionHeader(
            'assets/images/scorer_logo.png',
            'Buteurs',
            'Échelle commune · 0 à $scorerScale buts',
          ),
          ...scorers.map(
            (gauge) => _PlayerSummaryCard(
              gauge: gauge,
              currentUserId: currentUserId,
              scaleMax: scorerScale,
              onTap: () => _showPlayerDetails(gauge, currentUserId),
            ),
          ),
          const SizedBox(height: 18),
        ],
        if (keepers.isNotEmpty) ...[
          _sectionHeader(
            'assets/images/keeper_logo.png',
            'Gardiens',
            'Clean sheets · 0 à $keeperScale',
          ),
          ...keepers.map(
            (gauge) => _PlayerSummaryCard(
              gauge: gauge,
              currentUserId: currentUserId,
              scaleMax: keeperScale,
              onTap: () => _showPlayerDetails(gauge, currentUserId),
            ),
          ),
        ],
      ],
    );
  }

  Widget _predictorView(
    List<PlayerGauge> gauges,
    List<({String id, String name})> predictors,
    String? currentUserId,
  ) {
    final selectedId = _selectedPredictorId;
    final selectedEntries =
        predictors.where((entry) => entry.id == selectedId).toList();
    final selectedName =
        selectedEntries.isEmpty ? 'Pronostiqueur' : selectedEntries.first.name;
    final scorers = gauges.where((gauge) => !gauge.isGoalkeeper).toList();
    final keepers = gauges.where((gauge) => gauge.isGoalkeeper).toList();

    return Column(
      key: const ValueKey('predictors'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: selectedId,
          decoration: const InputDecoration(
            labelText: 'Consulter les pronostics de',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
          items: [
            for (final predictor in predictors)
              DropdownMenuItem(
                value: predictor.id,
                child: Text(
                  predictor.id == currentUserId
                      ? '${predictor.name} (moi)'
                      : predictor.name,
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _selectedPredictorId = value);
            }
          },
        ),
        const SizedBox(height: 18),
        Text(
          selectedName,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        Text(
          'Sa fiche complète de pronostics',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 18),
        if (scorers.isNotEmpty) ...[
          _compactSectionTitle('Buteurs'),
          _PredictorSheet(
            gauges: scorers,
            predictorId: selectedId,
            scaleMax: _sectionScale(scorers, defaultMax: 20),
          ),
          const SizedBox(height: 18),
        ],
        if (keepers.isNotEmpty) ...[
          _compactSectionTitle('Gardiens · clean sheets'),
          _PredictorSheet(
            gauges: keepers,
            predictorId: selectedId,
            scaleMax: _sectionScale(keepers, defaultMax: 15),
          ),
        ],
      ],
    );
  }

  Widget _sectionHeader(String asset, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Image.asset(asset, height: 38, fit: BoxFit.contain),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactSectionTitle(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }

  List<({String id, String name})> _predictorsFrom(List<PlayerGauge> gauges) {
    final byId = <String, String>{};
    for (final gauge in gauges) {
      for (final prediction in gauge.predictions) {
        byId[prediction.predictorId] = prediction.predictorName;
      }
    }
    final result = byId.entries
        .map((entry) => (id: entry.key, name: entry.value))
        .toList()
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    return result;
  }

  int _sectionScale(
    List<PlayerGauge> gauges, {
    required int defaultMax,
  }) {
    var observedMax = defaultMax;
    for (final gauge in gauges) {
      observedMax = math.max(observedMax, gauge.maxValue);
    }
    return ((observedMax + 4) ~/ 5) * 5;
  }

  Future<void> _showPlayerDetails(
    PlayerGauge gauge,
    String? currentUserId,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: .92,
          minChildSize: .65,
          maxChildSize: .98,
          builder: (context, scrollController) {
            return _PlayerDetailsSheet(
              gauge: gauge,
              currentUserId: currentUserId,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }

  Future<void> _saveAll(List<SeasonPredictionItem> items) async {
    setState(() {
      _isSavingAll = true;
      _error = null;
    });
    try {
      final repository = ref.read(seasonPredictionsRepositoryProvider);
      for (final item in items) {
        final key = '${item.playerId}:${item.category}';
        final value = _draftValues[key] ?? item.value;
        await repository.save(item.copyWith(value: value, isFilled: true));
      }
      _draftValues.clear();
      ref.invalidate(seasonPredictionsProvider);
      ref.invalidate(seasonGaugesProvider);
      await ref.read(seasonPredictionsProvider.future);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pronostics enregistrés.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = humanizeError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingAll = false);
      }
    }
  }
}

class _PlayerSummaryCard extends StatelessWidget {
  const _PlayerSummaryCard({
    required this.gauge,
    required this.currentUserId,
    required this.scaleMax,
    required this.onTap,
  });

  final PlayerGauge gauge;
  final String? currentUserId;
  final int scaleMax;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = gauge.predictionFor(currentUserId);
    final optimistic = gauge.predictions.take(3).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          gauge.playerName,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: onTap,
                    icon: const Icon(Icons.chevron_right, size: 18),
                    label: Text('Voir les ${gauge.predictions.length}'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                      label: 'Médiane du groupe',
                      value: _formatNumber(gauge.median),
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Metric(
                      label: 'Mon prono',
                      value: mine?.value.toString() ?? '—',
                      color: Colors.greenAccent.shade400,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ComparisonGauge(
                actual: gauge.actual,
                median: gauge.median,
                mine: mine?.value,
                maxValue: scaleMax,
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Text(
                    gauge.predictions.isEmpty
                        ? 'Aucun prono'
                        : 'Min ${gauge.minimum}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  Text(
                    gauge.predictions.isEmpty ? '' : 'Max ${gauge.maximum}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              if (optimistic.isNotEmpty) ...[
                const Divider(height: 24),
                Text(
                  'Plus optimistes',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 8,
                  runSpacing: 7,
                  children: [
                    for (final prediction in optimistic)
                      _OptimistChip(prediction: prediction),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
        ),
      ],
    );
  }
}

class _OptimistChip extends StatelessWidget {
  const _OptimistChip({required this.prediction});

  final GaugePrediction prediction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = prediction.predictorName.isEmpty
        ? '?'
        : prediction.predictorName.substring(0, 1).toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: scheme.primaryContainer,
            child: Text(
              initial,
              style: TextStyle(
                color: scheme.onPrimaryContainer,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(prediction.predictorName),
          const SizedBox(width: 5),
          Text(
            '${prediction.value}',
            style: TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonGauge extends StatelessWidget {
  const _ComparisonGauge({
    required this.actual,
    required this.median,
    required this.mine,
    required this.maxValue,
  });

  final int actual;
  final double median;
  final int? mine;
  final int maxValue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        SizedBox(
          height: 62,
          child: CustomPaint(
            painter: _GaugePainter(
              actual: actual.toDouble(),
              median: median,
              mine: mine?.toDouble(),
              maxValue: maxValue.toDouble(),
              lineColor: scheme.outlineVariant,
              actualColor: scheme.primary,
              medianColor: scheme.tertiary,
              mineColor: Colors.greenAccent.shade400,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        Row(
          children: [
            Text('0', style: Theme.of(context).textTheme.labelSmall),
            const Spacer(),
            Text('$maxValue', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.actual,
    required this.median,
    required this.mine,
    required this.maxValue,
    required this.lineColor,
    required this.actualColor,
    required this.medianColor,
    required this.mineColor,
  });

  final double actual;
  final double median;
  final double? mine;
  final double maxValue;
  final Color lineColor;
  final Color actualColor;
  final Color medianColor;
  final Color mineColor;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 9.0;
    final right = size.width - 9;
    const y = 28.0;
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(left, y), Offset(right, y), linePaint);

    double xFor(double value) {
      final safeMax = math.max(1.0, maxValue);
      final ratio = (value / safeMax).clamp(0.0, 1.0).toDouble();
      return left + ((right - left) * ratio);
    }

    final actualX = xFor(actual);
    canvas.drawCircle(
      Offset(actualX, y),
      8,
      Paint()..color = actualColor,
    );
    _drawLabel(canvas, '$actual'.replaceAll('.0', ''), actualX, 45, actualColor);

    final medianX = xFor(median);
    final triangle = Path()
      ..moveTo(medianX, y - 11)
      ..lineTo(medianX - 8, y + 4)
      ..lineTo(medianX + 8, y + 4)
      ..close();
    canvas.drawPath(triangle, Paint()..color = medianColor);
    _drawLabel(canvas, _formatNumber(median), medianX, 4, medianColor);

    if (mine != null) {
      final mineX = xFor(mine!);
      final diamond = Path()
        ..moveTo(mineX, y - 9)
        ..lineTo(mineX + 8, y)
        ..lineTo(mineX, y + 9)
        ..lineTo(mineX - 8, y)
        ..close();
      canvas.drawPath(diamond, Paint()..color = mineColor);
      _drawLabel(
        canvas,
        '${mine!}'.replaceAll('.0', ''),
        mineX,
        45,
        mineColor,
      );
    }
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    double x,
    double y,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(x - (painter.width / 2), y));
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.actual != actual ||
        oldDelegate.median != median ||
        oldDelegate.mine != mine ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.actualColor != actualColor ||
        oldDelegate.medianColor != medianColor ||
        oldDelegate.mineColor != mineColor;
  }
}

class _PredictorSheet extends StatelessWidget {
  const _PredictorSheet({
    required this.gauges,
    required this.predictorId,
    required this.scaleMax,
  });

  final List<PlayerGauge> gauges;
  final String? predictorId;
  final int scaleMax;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (var index = 0; index < gauges.length; index++) ...[
              _PredictorRow(
                gauge: gauges[index],
                prediction: gauges[index].predictionFor(predictorId),
                scaleMax: scaleMax,
              ),
              if (index != gauges.length - 1)
                Divider(height: 1, color: scheme.outlineVariant),
            ],
          ],
        ),
      ),
    );
  }
}

class _PredictorRow extends StatelessWidget {
  const _PredictorRow({
    required this.gauge,
    required this.prediction,
    required this.scaleMax,
  });

  final PlayerGauge gauge;
  final GaugePrediction? prediction;
  final int scaleMax;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = ((prediction?.value ?? 0) / math.max(1, scaleMax))
        .clamp(0.0, 1.0)
        .toDouble();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              gauge.playerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Actuel ${gauge.actual}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 34,
            child: Text(
              prediction?.value.toString() ?? '—',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerDetailsSheet extends StatelessWidget {
  const _PlayerDetailsSheet({
    required this.gauge,
    required this.currentUserId,
    required this.scrollController,
  });

  final PlayerGauge gauge;
  final String? currentUserId;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final predictions = [...gauge.predictions];
    final maxValue = math.max(1, gauge.maximum);
    final buckets = _distributionBuckets(gauge);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        Center(
          child: Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
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
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const Text('Détail des pronostics'),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                gauge.isGoalkeeper
                    ? AppFormats.counted(
                        gauge.actual,
                        'clean sheet',
                        'clean sheets',
                      )
                    : AppFormats.counted(gauge.actual, 'but'),
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Médiane',
                value: _formatNumber(gauge.median),
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(
                label: 'Moyenne',
                value: gauge.average.toStringAsFixed(1).replaceAll('.', ','),
                color: scheme.tertiary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(
                label: 'Écart',
                value: gauge.predictions.isEmpty
                    ? '—'
                    : '${gauge.minimum}–${gauge.maximum}',
                color: Colors.amberAccent.shade400,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Distribution des pronostics',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 16),
                _DistributionChart(
                  buckets: buckets,
                  total: gauge.predictions.length,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Tous les pronostics (${predictions.length})',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 10),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (var index = 0; index < predictions.length; index++)
                  _RankingRow(
                    prediction: predictions[index],
                    rank: _rankFor(predictions, index),
                    maxValue: maxValue,
                    isMine: predictions[index].predictorId == currentUserId,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'En cas d’égalité, le même rang est attribué.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  static List<({String label, int count})> _distributionBuckets(
    PlayerGauge gauge,
  ) {
    final maxValue = math.max(20, gauge.maximum);
    final step = maxValue <= 20 ? 5 : math.max(5, (maxValue / 4).ceil());
    final result = <({String label, int count})>[];

    for (var start = 0; start < step * 4; start += step) {
      final end = start + step - 1;
      final count = gauge.values
          .where((value) => value >= start && value <= end)
          .length;
      result.add((label: '$start–$end', count: count));
    }

    final lastStart = step * 4;
    result.add(
      (
        label: '$lastStart+',
        count: gauge.values.where((value) => value >= lastStart).length,
      ),
    );
    return result;
  }

  static int _rankFor(List<GaugePrediction> predictions, int index) {
    if (index == 0) return 1;
    if (predictions[index].value == predictions[index - 1].value) {
      return _rankFor(predictions, index - 1);
    }
    return index + 1;
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

class _DistributionChart extends StatelessWidget {
  const _DistributionChart({
    required this.buckets,
    required this.total,
  });

  final List<({String label, int count})> buckets;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var maxCount = 1;
    for (final bucket in buckets) {
      maxCount = math.max(maxCount, bucket.count);
    }

    return SizedBox(
      height: 145,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final bucket in buckets)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${bucket.count}',
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      total == 0
                          ? '0 %'
                          : '${(bucket.count * 100 / total).round()} %',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 5),
                    Flexible(
                      child: FractionallySizedBox(
                        heightFactor: bucket.count / maxCount,
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 3),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(7),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      bucket.label,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.prediction,
    required this.rank,
    required this.maxValue,
    required this.isMine,
  });

  final GaugePrediction prediction;
  final int rank;
  final int maxValue;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = (prediction.value / maxValue).clamp(0.0, 1.0).toDouble();
    final medalColor = switch (rank) {
      1 => Colors.amber,
      2 => Colors.blueGrey.shade200,
      3 => Colors.deepOrange.shade300,
      _ => scheme.onSurfaceVariant,
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: isMine ? Colors.green.withOpacity(.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: rank <= 3
                ? CircleAvatar(
                    radius: 11,
                    backgroundColor: medalColor,
                    child: Text(
                      '$rank',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  )
                : Text('$rank'),
          ),
          Expanded(
            flex: 3,
            child: Text(
              isMine
                  ? '${prediction.predictorName} (moi)'
                  : prediction.predictorName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isMine ? Colors.greenAccent.shade400 : null,
                fontWeight: isMine ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: scheme.surfaceContainerHighest,
                color: isMine ? Colors.greenAccent.shade400 : scheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 28,
            child: Text(
              '${prediction.value}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatNumber(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(1).replaceAll('.', ',');
}
