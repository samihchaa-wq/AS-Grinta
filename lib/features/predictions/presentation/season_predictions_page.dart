import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final seasonPredictionsProvider =
    FutureProvider<List<SeasonPredictionItem>>((ref) {
  return ref.watch(seasonPredictionsRepositoryProvider).fetchMine();
});

final publicSeasonPredictionsProvider =
    FutureProvider<List<SeasonPredictionItem>>((ref) {
  return ref.watch(seasonPredictionsRepositoryProvider).fetchPublic();
});

class SeasonPredictionsPage extends ConsumerStatefulWidget {
  const SeasonPredictionsPage({super.key});

  @override
  ConsumerState<SeasonPredictionsPage> createState() =>
      _SeasonPredictionsPageState();
}

class _SeasonPredictionsPageState extends ConsumerState<SeasonPredictionsPage> {
  final Map<String, int> _draftValues = {};
  String? _savingKey;
  String? _error;
  bool _showPublic = false;

  @override
  Widget build(BuildContext context) {
    final mineAsync = ref.watch(seasonPredictionsProvider);
    final publicAsync = ref.watch(publicSeasonPredictionsProvider);

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
                  label: Text('Mes pronostics'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.public),
                  label: Text('Pronostics publics'),
                ),
              ],
              selected: {_showPublic},
              onSelectionChanged: (selection) {
                setState(() => _showPublic = selection.first);
              },
            ),
          ),
          Expanded(
            child:
                _showPublic ? _buildPublic(publicAsync) : _buildMine(mineAsync),
          ),
        ],
      ),
    );
  }

  Widget _buildMine(AsyncValue<List<SeasonPredictionItem>> asyncItems) {
    return RefreshIndicator(
      onRefresh: () async {
        _draftValues.clear();
        ref.invalidate(seasonPredictionsProvider);
        await ref.read(seasonPredictionsProvider.future);
      },
      child: asyncItems.when(
        loading: () => ListView(
          children: [
            SizedBox(height: 220),
            Center(child: CircularProgressIndicator()),
          ],
        ),
        error: (error, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [Text(error.toString())],
        ),
        data: (items) {
          if (items.isEmpty) {
            return ListView(
              padding: EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Aucune saison ouverte ou aucun joueur actif dans l’effectif.',
                    ),
                  ),
                ),
              ],
            );
          }

          final grouped = <String, List<SeasonPredictionItem>>{};
          for (final item in items) {
            grouped.putIfAbsent(item.playerId, () => []).add(item);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Valeurs prévues pour 20 matchs. Une ligne jamais enregistrée rapporte 0 point.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              ...grouped.values.map((playerItems) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          playerItems.first.playerName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        ...playerItems.map(_buildPredictionRow),
                      ],
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPublic(AsyncValue<List<SeasonPredictionItem>> asyncItems) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(publicSeasonPredictionsProvider);
        await ref.read(publicSeasonPredictionsProvider.future);
      },
      child: asyncItems.when(
        loading: () => ListView(
          children: [
            SizedBox(height: 220),
            Center(child: CircularProgressIndicator()),
          ],
        ),
        error: (error, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [Text(error.toString())],
        ),
        data: (items) {
          if (items.isEmpty) {
            return ListView(
              padding: EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Aucun pronostic public enregistré.'),
                  ),
                ),
              ],
            );
          }

          final grouped = <String, List<SeasonPredictionItem>>{};
          for (final item in items) {
            grouped.putIfAbsent(item.predictorId, () => []).add(item);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: grouped.values.map((predictions) {
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  title: Text(predictions.first.predictorName),
                  subtitle:
                      Text('${predictions.length} prédiction(s) saisie(s)'),
                  children: predictions
                      .map(
                        (item) => ListTile(
                          title: Text(item.playerName),
                          subtitle: Text(_categoryLabel(item.category)),
                          trailing: Text(
                            '${item.value}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      )
                      .toList(),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildPredictionRow(SeasonPredictionItem item) {
    final key = '${item.playerId}:${item.category}';
    final value = _draftValues[key] ?? item.value;
    final isSaving = _savingKey == key;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(child: Text(_categoryLabel(item.category))),
          IconButton(
            onPressed: isSaving || value <= 0
                ? null
                : () => setState(() => _draftValues[key] = value - 1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            onPressed: isSaving
                ? null
                : () => setState(() => _draftValues[key] = value + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
          FilledButton(
            onPressed: isSaving ? null : () => _save(item, value, key),
            child: isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(item.isFilled ? 'Modifier' : 'Enregistrer'),
          ),
        ],
      ),
    );
  }

  Future<void> _save(
    SeasonPredictionItem item,
    int value,
    String key,
  ) async {
    setState(() {
      _savingKey = key;
      _error = null;
    });
    try {
      await ref.read(seasonPredictionsRepositoryProvider).save(
            item.copyWith(value: value, isFilled: true),
          );
      ref.invalidate(seasonPredictionsProvider);
      ref.invalidate(publicSeasonPredictionsProvider);
      await ref.read(seasonPredictionsProvider.future);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _savingKey = null);
    }
  }

  String _categoryLabel(String category) {
    return switch (category) {
      'buts' => 'Buts',
      'passes' => 'Passes décisives',
      'hommes_du_match' => 'Hommes du match',
      'clean_sheets' => 'Clean sheets',
      _ => category,
    };
  }
}
