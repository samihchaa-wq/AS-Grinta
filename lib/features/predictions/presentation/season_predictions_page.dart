import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

const _kSeasonExplanation =
    'Les pronostics portent sur une saison complète de 30 matchs. Peu importe '
    'le nombre de matchs réellement disputés par un joueur (blessure, arrivée '
    'en cours de saison, suspension, etc.). Les classements affichés pendant '
    'la saison sont calculés à partir d’une projection sur 30 matchs et '
    'évolueront jusqu’à la fin de la saison.';

class SeasonPredictionsPage extends ConsumerStatefulWidget {
  const SeasonPredictionsPage({super.key});

  @override
  ConsumerState<SeasonPredictionsPage> createState() =>
      _SeasonPredictionsPageState();
}

class _SeasonPredictionsPageState extends ConsumerState<SeasonPredictionsPage> {
  final Map<String, int> _draftValues = {};
  String? _error;
  bool _showGauges = false;
  bool _isSavingAll = false;
  bool _locked = false;

  @override
  Widget build(BuildContext context) {
    final mineAsync = ref.watch(seasonPredictionsProvider);
    final gaugesAsync = ref.watch(seasonGaugesProvider);
    _locked = ref.watch(seasonPredictionsLockedProvider).valueOrNull ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Pronostics de saison')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.edit_outlined),
                  label: Text('Mes pronos'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.leaderboard_outlined),
                  label: Text('Jauges'),
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
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(_kSeasonExplanation),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pour chaque joueur : le nombre de buts que tu prévois sur la '
                'saison (les clean sheets pour le gardien).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.playerName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            SizedBox(
              width: 84,
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
                    'Les pronostics de tout le monde seront révélés ici une '
                    'fois que l’admin aura verrouillé les paris de la saison. '
                    'D’ici là, personne ne voit les pronostics des autres.',
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
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Le curseur ▮ montre le total réel actuel. Les repères ● '
                    'sont les pronostics. La jauge grandit si un joueur '
                    'dépasse le plus gros pronostic.',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ...gauges.map((gauge) => _GaugeCard(gauge: gauge)),
            ],
          );
        },
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
    final label = gauge.isGoalkeeper ? 'clean sheets' : 'buts';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    gauge.playerName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${gauge.actual} $label',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _GaugeBar(gauge: gauge),
            const SizedBox(height: 6),
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
        double posOf(int value) =>
            (value / maxValue).clamp(0.0, 1.0) * width;

        return SizedBox(
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Piste
              Positioned(
                left: 0,
                right: 0,
                top: 20,
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
                top: 20,
                child: Container(
                  height: 6,
                  width: posOf(gauge.actual),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              // Repères des pronostics
              for (final marker in gauge.markers)
                Positioned(
                  left: (posOf(marker.value) - 11).clamp(0.0, width - 22),
                  top: 6,
                  child: _MarkerDot(
                    marker: marker,
                    playerName: gauge.playerName,
                  ),
                ),
              // Curseur réel
              Positioned(
                left: (posOf(gauge.actual) - 3).clamp(0.0, width - 6),
                top: 12,
                child: Container(
                  width: 6,
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

class _MarkerDot extends StatelessWidget {
  const _MarkerDot({required this.marker, required this.playerName});

  final GaugeMarker marker;
  final String playerName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = marker.predictorNames.length;
    return GestureDetector(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              '$playerName — pronostic ${marker.value}',
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...marker.predictorNames.map(
              (name) => ListTile(
                dense: true,
                leading: const Icon(Icons.person_outline),
                title: Text(name),
              ),
            ),
          ],
        ),
      ),
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          shape: BoxShape.circle,
          border: Border.all(color: scheme.tertiary),
        ),
        child: count > 1
            ? Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: scheme.onTertiaryContainer,
                ),
              )
            : Icon(Icons.circle, size: 8, color: scheme.tertiary),
      ),
    );
  }
}
