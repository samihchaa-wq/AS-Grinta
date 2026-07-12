import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// autoDispose : ces états (verrou, pronos, jauges) sont relus à chaque ouverture
// de l'écran. Sinon, si l'admin déverrouille les paris après avoir consulté la
// page une fois, la valeur « verrouillé » resterait en cache et les champs
// resteraient bloqués.
final seasonPredictionsProvider =
    FutureProvider.autoDispose<List<SeasonPredictionItem>>((ref) {
  return ref.watch(seasonPredictionsRepositoryProvider).fetchMine();
});

final seasonGaugesProvider =
    FutureProvider.autoDispose<List<PlayerGauge>>((ref) {
  return ref.watch(seasonPredictionsRepositoryProvider).fetchGauges();
});

/// Pronostics de saison fermés par le staff (ou aucune saison ouverte).
final seasonPredictionsLockedProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(seasonPredictionsRepositoryProvider).isLocked();
});

class SeasonPredictionsPage extends ConsumerStatefulWidget {
  const SeasonPredictionsPage({
    super.key,
    this.openMine = false,
    this.gaugesOnly = false,
  });

  /// Ouvre directement l'onglet « Mes pronos » (édition) plutôt que « Jauges ».
  final bool openMine;

  /// Affiche uniquement les jauges (onglet Pronos), avec un bouton pour éditer.
  final bool gaugesOnly;

  @override
  ConsumerState<SeasonPredictionsPage> createState() =>
      _SeasonPredictionsPageState();
}

class _SeasonPredictionsPageState extends ConsumerState<SeasonPredictionsPage> {
  final Map<String, int> _draftValues = {};
  String? _error;
  late bool _showGauges = !widget.openMine;
  bool _isSavingAll = false;
  bool _locked = false;

  @override
  Widget build(BuildContext context) {
    final mineAsync = ref.watch(seasonPredictionsProvider);
    final gaugesAsync = ref.watch(seasonGaugesProvider);
    _locked = ref.watch(seasonPredictionsLockedProvider).valueOrNull ?? false;

    if (widget.gaugesOnly) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Pronostics'),
          actions: [
            IconButton(
              tooltip: 'Modifier mes pronostics',
              icon: const Icon(Icons.edit_calendar_outlined),
              onPressed: () => context.push('/predictions/season?tab=mine'),
            ),
          ],
        ),
        body: _buildGauges(gaugesAsync),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pronostics de saison')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.leaderboard_outlined),
                  label: Text('Jauges'),
                ),
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.edit_outlined),
                  label: Text('Mes pronos'),
                ),
              ],
              selected: {_showGauges},
              onSelectionChanged: (selection) {
                setState(() => _showGauges = selection.first);
              },
            ),
          ),
          Expanded(
            child: _showGauges
                ? _buildGauges(gaugesAsync)
                : _buildMine(mineAsync),
          ),
        ],
      ),
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
              if (_locked)
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: const ListTile(
                    leading: Icon(Icons.lock_outline),
                    title: Text('Pronostics de saison fermés'),
                    subtitle: Text(
                      'Ils ne sont plus modifiables. Va dans « Jauges » pour '
                      'suivre l’évolution.',
                    ),
                  ),
                ),
              if (_locked) const SizedBox(height: 12),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              ...items.map(_buildPlayerRow),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      _isSavingAll || _locked ? null : () => _saveAll(items),
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
                        : _locked
                            ? 'Pronostics fermés'
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
                enabled: !_locked,
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
    if (!_locked) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.visibility_off_outlined, size: 40),
                  SizedBox(height: 12),
                  Text(
                    'Pronostics révélés au verrouillage.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
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
          final buteurs = gauges.where((g) => !g.isGoalkeeper).toList();
          final gardiens = gauges.where((g) => g.isGoalkeeper).toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (buteurs.isNotEmpty) ...[
                _sectionHeader('assets/images/scorer_logo.png', 'Buts'),
                ...buteurs.map((gauge) => _GaugeCard(gauge: gauge)),
                const SizedBox(height: 16),
              ],
              if (gardiens.isNotEmpty) ...[
                _sectionHeader('assets/images/keeper_logo.png', 'Clean sheets'),
                ...gardiens.map((gauge) => _GaugeCard(gauge: gauge)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(String asset, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 10),
      child: Row(
        children: [
          Image.asset(asset, height: 36, fit: BoxFit.contain),
          const SizedBox(width: 10),
          Text(label, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
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

class _GaugeCard extends StatelessWidget {
  const _GaugeCard({required this.gauge});

  final PlayerGauge gauge;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              gauge.playerName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            _GaugeBar(gauge: gauge),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0', style: Theme.of(context).textTheme.bodySmall),
                Text('${gauge.maxValue}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GaugeBar extends StatelessWidget {
  const _GaugeBar({required this.gauge});

  final PlayerGauge gauge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxValue = gauge.maxValue <= 0 ? 1 : gauge.maxValue;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        double posOf(int value) => (value / maxValue).clamp(0.0, 1.0) * width;

        const labelW = 74.0;
        Widget label(double x, String text, Color color, FontWeight weight) {
          return Positioned(
            top: 2,
            left: (x - labelW / 2).clamp(0.0, width - labelW),
            width: labelW,
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                height: 1.1,
                fontWeight: weight,
                color: color,
              ),
            ),
          );
        }

        return SizedBox(
          height: 52,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Noms des pronostiqueurs, au-dessus de chaque repère rose.
              for (final marker in gauge.markers)
                label(
                  posOf(marker.value),
                  marker.predictorNames.join(', '),
                  scheme.tertiary,
                  FontWeight.w600,
                ),
              // Total réel, au-dessus du curseur bleu.
              label(
                posOf(gauge.actual),
                '${gauge.actual}',
                scheme.primary,
                FontWeight.w900,
              ),
              // Piste
              Positioned(
                left: 0,
                right: 0,
                top: 36,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              // Progression réelle
              Positioned(
                left: 0,
                top: 36,
                child: Container(
                  height: 6,
                  width: posOf(gauge.actual),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              // Repères des pronostics (points roses)
              for (final marker in gauge.markers)
                Positioned(
                  left: (posOf(marker.value) - 6).clamp(0.0, width - 12),
                  top: 33,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.tertiary, width: 2),
                    ),
                  ),
                ),
              // Curseur réel (barre bleue)
              Positioned(
                left: (posOf(gauge.actual) - 2.5).clamp(0.0, width - 5),
                top: 28,
                child: Container(
                  width: 5,
                  height: 22,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(3),
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
