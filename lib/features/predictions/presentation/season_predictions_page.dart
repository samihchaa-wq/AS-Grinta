import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final seasonPredictionsProvider = FutureProvider<List<SeasonPredictionItem>>(
  (ref) => ref.watch(seasonPredictionsRepositoryProvider).fetchMine(),
);
final publicSeasonPredictionsProvider = FutureProvider<List<SeasonPredictionItem>>(
  (ref) => ref.watch(seasonPredictionsRepositoryProvider).fetchPublic(),
);

class SeasonPredictionsPage extends ConsumerStatefulWidget {
  const SeasonPredictionsPage({super.key});
  @override
  ConsumerState<SeasonPredictionsPage> createState() => _SeasonPredictionsPageState();
}

class _SeasonPredictionsPageState extends ConsumerState<SeasonPredictionsPage> {
  final _draft = <String, int>{};
  bool _public = false;
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_public ? publicSeasonPredictionsProvider : seasonPredictionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Pronostics de saison')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Mes pronostics'), icon: Icon(Icons.edit_outlined)),
              ButtonSegment(value: true, label: Text('Pronostics publics'), icon: Icon(Icons.public)),
            ],
            selected: {_public},
            onSelectionChanged: (value) => setState(() => _public = value.first),
          ),
        ),
        Expanded(child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text('Pronostics temporairement indisponibles.')),
          data: (items) => _public ? _publicList(items) : _mine(items),
        )),
      ]),
    );
  }

  Widget _mine(List<SeasonPredictionItem> items) {
    if (items.isEmpty) return const Center(child: Text('Aucune saison ouverte.'));
    final grouped = <String, List<SeasonPredictionItem>>{};
    for (final item in items) grouped.putIfAbsent(item.playerId, () => []).add(item);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        const Text('Prévisions pour 20 matchs : buts, passes, HDM, clean sheets et fautes provoquant un penalty.'),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 12),
        ...grouped.values.map((playerItems) => Card(
          child: ExpansionTile(
            title: Text(playerItems.first.playerName),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: playerItems.map((item) => Row(children: [
              Expanded(child: Text(_categoryLabel(item.category))),
              SizedBox(
                width: 90,
                child: TextFormField(
                  initialValue: '${_draft['${item.playerId}:${item.category}'] ?? item.value}',
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (raw) => _draft['${item.playerId}:${item.category}'] = int.tryParse(raw) ?? 0,
                ),
              ),
            ])).toList(),
          ),
        )),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saving ? null : () => _save(items),
          icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_circle_outline),
          label: const Text('Valider mes pronostics'),
        ),
      ],
    );
  }

  Widget _publicList(List<SeasonPredictionItem> items) {
    if (items.isEmpty) return const Center(child: Text('Aucun pronostic public.'));
    final grouped = <String, List<SeasonPredictionItem>>{};
    for (final item in items) grouped.putIfAbsent(item.predictorId, () => []).add(item);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: grouped.values.map((list) => Card(
        child: ExpansionTile(
          title: Text(list.first.predictorName),
          children: list.map((item) => ListTile(
            title: Text(item.playerName),
            subtitle: Text(_categoryLabel(item.category)),
            trailing: Text('${item.value}'),
          )).toList(),
        ),
      )).toList(),
    );
  }

  Future<void> _save(List<SeasonPredictionItem> items) async {
    setState(() { _saving = true; _error = null; });
    try {
      final repository = ref.read(seasonPredictionsRepositoryProvider);
      for (final item in items) {
        final value = _draft['${item.playerId}:${item.category}'] ?? item.value;
        await repository.save(item.copyWith(value: value, isFilled: true));
      }
      ref.invalidate(seasonPredictionsProvider);
      ref.invalidate(publicSeasonPredictionsProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pronostics enregistrés.')));
    } catch (_) {
      if (mounted) setState(() => _error = 'Les pronostics n’ont pas pu être enregistrés.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _categoryLabel(String category) => switch (category) {
    'buts' => 'Buts',
    'passes' => 'Passes décisives',
    'hommes_du_match' => 'Hommes du match',
    'clean_sheets' => 'Clean sheets',
    'penalty_faults' => 'Fautes provoquant un penalty',
    _ => category,
  };
}
