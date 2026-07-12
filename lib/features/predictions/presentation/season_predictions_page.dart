import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
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
  bool _locked = false;

  @override
  Widget build(BuildContext context) {
    final mineAsync = ref.watch(seasonPredictionsProvider);
    final gaugesAsync = ref.watch(seasonGaugesProvider);
    _locked = ref.watch(seasonPredictionsLockedProvider).valueOrNull ?? false;

    // Paris ouverts : chacun saisit ses pronos. Une fois fermés par l'admin,
    // on bascule sur les jauges (les pronos de tout le monde sont révélés).
    return Scaffold(
      appBar: AppBar(
        title: Text(_locked ? 'Jauges de saison' : 'Mes pronos de saison'),
      ),
      body: _locked ? _buildGauges(gaugesAsync) : _buildMine(mineAsync),
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
    final scheme = Theme.of(context).colorScheme;

    // Un pronostic par pronostiqueur, trié par valeur croissante puis par nom.
    final preds = <({String name, int value})>[];
    for (final marker in gauge.markers) {
      for (final name in marker.predictorNames) {
        preds.add((name: name, value: marker.value));
      }
    }
    preds.sort((a, b) {
      final byValue = a.value.compareTo(b.value);
      return byValue != 0
          ? byValue
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
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
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    gauge.isGoalkeeper
                        ? AppFormats.counted(
                            gauge.actual, 'clean sheet', 'clean sheets')
                        : AppFormats.counted(gauge.actual, 'but'),
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (preds.isEmpty)
              Text(
                'Aucun pronostic.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in preds)
                    _PredChip(name: p.name, value: p.value),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Un pronostic « Nom valeur » sous forme de pastille, qui passe à la ligne
/// automatiquement (lisible même avec beaucoup de pronostiqueurs).
class _PredChip extends StatelessWidget {
  const _PredChip({required this.name, required this.value});

  final String name;
  final int value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 6),
          Text(
            '$value',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: scheme.tertiary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
