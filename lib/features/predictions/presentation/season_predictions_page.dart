import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  String? _error;
  bool _showPublic = false;
  bool _isSavingAll = false;

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
    return asyncItems.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [Text(error.toString())],
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

        return RefreshIndicator(
          onRefresh: () async {
            _draftValues.clear();
            ref.invalidate(seasonPredictionsProvider);
            await ref.read(seasonPredictionsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Valeurs prévues pour 30 matchs. Une case vide rapporte 0 point.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Les joueurs de champ ont Buts, Passes D. et HDM. Les gardiens ont uniquement Clean sheets.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 18,
                    horizontalMargin: 16,
                    columns: const [
                      DataColumn(label: Text('Joueur')),
                      DataColumn(label: Text('Buts')),
                      DataColumn(label: Text('Passes D.')),
                      DataColumn(label: Text('HDM')),
                      DataColumn(label: Text('Clean sheets')),
                    ],
                    rows: grouped.values.map(_buildPredictionTableRow).toList(),
                  ),
                ),
              ),
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

  DataRow _buildPredictionTableRow(List<SeasonPredictionItem> playerItems) {
    SeasonPredictionItem? find(String category) {
      for (final item in playerItems) {
        if (item.category == category) return item;
      }
      return null;
    }

    final isGoalkeeper = find('clean_sheets') != null;

    return DataRow(
      cells: [
        DataCell(
          SizedBox(
            width: 130,
            child: Text(
              playerItems.first.playerName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(isGoalkeeper ? _disabledCell() : _numberCell(find('buts'))),
        DataCell(isGoalkeeper ? _disabledCell() : _numberCell(find('passes'))),
        DataCell(
          isGoalkeeper ? _disabledCell() : _numberCell(find('hommes_du_match')),
        ),
        DataCell(
          isGoalkeeper ? _numberCell(find('clean_sheets')) : _disabledCell(),
        ),
      ],
    );
  }

  Widget _numberCell(SeasonPredictionItem? item) {
    if (item == null) return _disabledCell();
    final key = '${item.playerId}:${item.category}';
    final value = _draftValues[key] ?? item.value;

    return SizedBox(
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
        ),
        onChanged: (raw) {
          final parsed = int.tryParse(raw) ?? 0;
          _draftValues[key] = parsed;
        },
      ),
    );
  }

  Widget _disabledCell() {
    return const SizedBox(
      width: 72,
      child: Center(child: Text('—')),
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
          children: const [
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
              padding: const EdgeInsets.all(16),
              children: const [
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
                  subtitle: Text('${predictions.length} pronostic(s)'),
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
      ref.invalidate(publicSeasonPredictionsProvider);
      await ref.read(seasonPredictionsProvider.future);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pronostics enregistrés.')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isSavingAll = false);
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
