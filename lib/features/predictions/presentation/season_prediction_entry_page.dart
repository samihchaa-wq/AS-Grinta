import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final seasonPredictionsProvider =
    FutureProvider.autoDispose<List<SeasonPredictionItem>>((ref) {
  return ref.watch(seasonPredictionsRepositoryProvider).fetchMine();
});

final seasonPredictionsLockedProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(seasonPredictionsRepositoryProvider).isLocked();
});

/// Formulaire existant de saisie des pronostics joueurs avant verrouillage.
class SeasonPredictionEntryPage extends ConsumerStatefulWidget {
  const SeasonPredictionEntryPage({super.key});

  @override
  ConsumerState<SeasonPredictionEntryPage> createState() =>
      _SeasonPredictionEntryPageState();
}

class _SeasonPredictionEntryPageState
    extends ConsumerState<SeasonPredictionEntryPage> {
  final Map<String, int> _draftValues = {};
  String? _error;
  bool _isSavingAll = false;

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(seasonPredictionsProvider);

    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Mes pronos de saison')),
      body: RefreshIndicator(
        onRefresh: () async {
          _draftValues.clear();
          ref.invalidate(seasonPredictionsLockedProvider);
          ref.invalidate(seasonPredictionsProvider);
          await ref.read(seasonPredictionsProvider.future);
        },
        child: items.when(
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
          data: (entries) {
            if (entries.isEmpty) {
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

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 12),
                ],
                ...entries.map(_buildPlayerRow),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSavingAll ? null : () => _saveAll(entries),
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
            );
          },
        ),
      ),
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
