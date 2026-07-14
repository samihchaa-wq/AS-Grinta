import 'dart:math' as math;

import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final seasonPredictionsProvider =
    FutureProvider.autoDispose<List<SeasonPredictionItem>>((ref) {
  return ref.watch(seasonPredictionsRepositoryProvider).fetchMine();
});

final seasonGaugesProvider = FutureProvider.autoDispose<List<PlayerGauge>>((
  ref,
) {
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
      appBar: GrintaAppBar(
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
                Text(_error!, style: const TextStyle(color: Colors.white70)),
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
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
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
                    : _predictorView(gauges, predictors, currentUserId),
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
            (gauge) => _NeonGaugeCard(
              gauge: gauge,
              scaleMax: scorerScale,
              onOpenAll: () => _showPlayerDetails(gauge, currentUserId),
              onOpenMarker: (marker) => _showMarkerDetails(gauge, marker),
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
            (gauge) => _NeonGaugeCard(
              gauge: gauge,
              scaleMax: keeperScale,
              onOpenAll: () => _showPlayerDetails(gauge, currentUserId),
              onOpenMarker: (marker) => _showMarkerDetails(gauge, marker),
            ),
          ),
        ],
        const SizedBox(height: 12),
        const _GaugeLegend(),
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
          initialValue: selectedId,
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
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
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
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
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
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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
    final result =
        byId.entries.map((entry) => (id: entry.key, name: entry.value)).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return result;
  }

  int _sectionScale(List<PlayerGauge> gauges, {required int defaultMax}) {
    var observedMax = defaultMax;
    for (final gauge in gauges) {
      observedMax = math.max(observedMax, gauge.maxValue);
    }
    return ((observedMax + 4) ~/ 5) * 5;
  }

  Future<void> _showMarkerDetails(PlayerGauge gauge, GaugeMarker marker) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                gauge.playerName,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                '${marker.value} ${gauge.isGoalkeeper ? 'clean sheets' : 'buts'}',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                marker.predictions.length == 1
                    ? 'Pronostiqué par'
                    : 'Pronostiqué par ${marker.predictions.length} personnes',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final prediction in marker.predictions)
                    Chip(
                      avatar: CircleAvatar(
                        child: Text(_initial(prediction.predictorName)),
                      ),
                      label: Text(prediction.predictorName),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
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
          initialChildSize: .9,
          minChildSize: .62,
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
      if (mounted) setState(() => _error = humanizeError(error));
    } finally {
      if (mounted) setState(() => _isSavingAll = false);
    }
  }
}

class _NeonGaugeCard extends StatelessWidget {
  const _NeonGaugeCard({
    required this.gauge,
    required this.scaleMax,
    required this.onOpenAll,
    required this.onOpenMarker,
  });

  final PlayerGauge gauge;
  final int scaleMax;
  final VoidCallback onOpenAll;
  final ValueChanged<GaugeMarker> onOpenMarker;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final modeMarker = _modeMarker(gauge.markers);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.primary.withValues(alpha: .28)),
        gradient: LinearGradient(
          colors: [
            scheme.surfaceContainerHigh.withValues(alpha: .96),
            scheme.surfaceContainer.withValues(alpha: .88),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: .07),
            blurRadius: 22,
            spreadRadius: 1,
          ),
        ],
      ),
      child: InkWell(
        onTap: onOpenAll,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
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
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
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
                  OutlinedButton.icon(
                    onPressed: onOpenAll,
                    icon: const Icon(Icons.chevron_right, size: 18),
                    label: Text('Voir les ${gauge.predictions.length}'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _InteractiveNeonGauge(
                actual: gauge.actual,
                maxValue: scaleMax,
                markers: gauge.markers,
                modeMarker: modeMarker,
                onMarkerTap: onOpenMarker,
              ),
            ],
          ),
        ),
      ),
    );
  }

  GaugeMarker? _modeMarker(List<GaugeMarker> markers) {
    if (markers.isEmpty) return null;
    final sorted = [...markers]..sort((a, b) {
        final byCount = b.predictions.length.compareTo(a.predictions.length);
        if (byCount != 0) return byCount;
        return b.value.compareTo(a.value);
      });
    return sorted.first;
  }
}

class _InteractiveNeonGauge extends StatelessWidget {
  const _InteractiveNeonGauge({
    required this.actual,
    required this.maxValue,
    required this.markers,
    required this.modeMarker,
    required this.onMarkerTap,
  });

  final int actual;
  final int maxValue;
  final List<GaugeMarker> markers;
  final GaugeMarker? modeMarker;
  final ValueChanged<GaugeMarker> onMarkerTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        const edge = 16.0;
        final width = math.max(1.0, constraints.maxWidth - edge * 2);
        double xFor(num value) {
          final ratio = (value / math.max(1, maxValue)).clamp(0.0, 1.0);
          return edge + width * ratio;
        }

        return SizedBox(
          height: 86,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: edge,
                right: edge,
                top: 38,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    gradient: LinearGradient(
                      colors: [
                        scheme.primary.withValues(alpha: .95),
                        const Color(0xFF6B5CFF),
                        const Color(0xFFD64BC8),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: .28),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                ),
              ),
              for (final marker in markers)
                Positioned(
                  left: xFor(marker.value) - (marker == modeMarker ? 18 : 7),
                  top: marker == modeMarker ? 21 : 32,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onMarkerTap(marker),
                    child: marker == modeMarker
                        ? _PopularPredictionBubble(marker: marker)
                        : _PredictionDot(marker: marker),
                  ),
                ),
              Positioned(
                left: xFor(actual) - 18,
                top: 20,
                child: _CurrentBall(value: actual),
              ),
              Positioned(
                left: 0,
                bottom: 0,
                child: Text('0', style: Theme.of(context).textTheme.labelSmall),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Text(
                  '$maxValue',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CurrentBall extends StatelessWidget {
  const _CurrentBall({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.surface,
            border: Border.all(color: scheme.primary, width: 2),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: .55),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(Icons.sports_soccer, color: scheme.onSurface, size: 25),
        ),
        const SizedBox(height: 2),
        Text(
          '$value',
          style: TextStyle(
            color: scheme.primary,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _PredictionDot extends StatelessWidget {
  const _PredictionDot({required this.marker});

  final GaugeMarker marker;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = 10.0 + math.min(7, marker.predictions.length * 1.5);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.tertiary,
        border: Border.all(color: Colors.white.withValues(alpha: .35)),
        boxShadow: [
          BoxShadow(
            color: scheme.tertiary.withValues(alpha: .55),
            blurRadius: 10,
          ),
        ],
      ),
    );
  }
}

class _PopularPredictionBubble extends StatelessWidget {
  const _PopularPredictionBubble({required this.marker});

  final GaugeMarker marker;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.tertiary;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: .24),
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .6),
            blurRadius: 18,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Text(
        '${marker.value}',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _GaugeLegend extends StatelessWidget {
  const _GaugeLegend();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Wrap(
          spacing: 18,
          runSpacing: 10,
          children: [
            _LegendItem(
              icon: Icon(Icons.sports_soccer, color: scheme.primary, size: 19),
              label: 'Buts actuels',
            ),
            _LegendItem(
              icon: Icon(Icons.circle, color: scheme.tertiary, size: 12),
              label: 'Chaque point = un score pronostiqué',
            ),
            const _LegendItem(
              icon: Icon(Icons.touch_app_outlined, size: 18),
              label: 'Appuie sur un point pour voir les noms',
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.icon, required this.label});

  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [icon, const SizedBox(width: 7), Text(label)],
    );
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
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Tous les pronostics (${predictions.length})',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
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
      ],
    );
  }

  static int _rankFor(List<GaugePrediction> predictions, int index) {
    if (index == 0) return 1;
    if (predictions[index].value == predictions[index - 1].value) {
      return _rankFor(predictions, index - 1);
    }
    return index + 1;
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
        color:
            isMine ? Colors.green.withValues(alpha: .16) : Colors.transparent,
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

String _initial(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
}
