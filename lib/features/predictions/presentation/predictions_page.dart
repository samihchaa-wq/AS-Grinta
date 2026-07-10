import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/features/predictions/data/leaderboard_repository.dart';
import 'package:as_grinta/features/predictions/data/predictions_repository.dart';
import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:as_grinta/features/predictions/presentation/predictions_controller.dart';
import 'package:as_grinta/features/predictions/presentation/season_predictions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class PredictionsPage extends ConsumerStatefulWidget {
  const PredictionsPage({super.key});

  @override
  ConsumerState<PredictionsPage> createState() => _PredictionsPageState();
}

class _PredictionsPageState extends ConsumerState<PredictionsPage> {
  String? _selectedPredictorId;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(predictionsControllerProvider.notifier).load(),
    );
  }

  Future<void> _refresh() async {
    await ref.read(predictionsControllerProvider.notifier).load();
    ref.invalidate(leaderboardProvider);
    ref.invalidate(publicSeasonPredictionsProvider);
    await Future.wait([
      ref.read(leaderboardProvider.future),
      ref.read(publicSeasonPredictionsProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final predictionState = ref.watch(predictionsControllerProvider);
    final leaderboardAsync = ref.watch(leaderboardProvider);
    final publicSeasonAsync = ref.watch(publicSeasonPredictionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pronostics'),
        actions: [
          IconButton(
            tooltip: 'Pronostics de saison',
            onPressed: () => context.push('/predictions/season'),
            icon: const Icon(Icons.edit_calendar_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Text('Prochain match', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            if (predictionState.error != null)
              _ErrorCard(message: predictionState.error!),
            if (predictionState.isLoading)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (predictionState.items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Aucun prochain match disponible.'),
                ),
              )
            else
              _PredictionCard(
                item: predictionState.items.first,
                isSaving: predictionState.savingMatchId ==
                    predictionState.items.first.matchId,
              ),
            const SizedBox(height: 24),
            Text(
              'Classement général',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            leaderboardAsync.when(
              loading: () => const Card(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (_, __) => const _ErrorCard(
                message: 'Le classement est temporairement indisponible.',
              ),
              data: (entries) => _LeaderboardCard(entries: entries),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Pronostics de saison',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => context.push('/predictions/season'),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Modifier'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            publicSeasonAsync.when(
              loading: () => const Card(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (_, __) => const _ErrorCard(
                message: 'Les pronostics de saison sont indisponibles.',
              ),
              data: _seasonPredictions,
            ),
          ],
        ),
      ),
    );
  }

  Widget _seasonPredictions(List<SeasonPredictionItem> items) {
    if (items.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Aucun pronostic de saison public.'),
        ),
      );
    }

    final grouped = <String, List<SeasonPredictionItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.predictorId, () => []).add(item);
    }
    final predictors = grouped.entries.toList()
      ..sort((a, b) => a.value.first.predictorName
          .toLowerCase()
          .compareTo(b.value.first.predictorName.toLowerCase()));
    final availableIds = predictors.map((entry) => entry.key).toSet();
    final selectedId = availableIds.contains(_selectedPredictorId)
        ? _selectedPredictorId!
        : predictors.first.key;
    final selected = [...grouped[selectedId]!]
      ..sort((a, b) {
        final player = a.playerName.compareTo(b.playerName);
        return player != 0 ? player : a.category.compareTo(b.category);
      });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: selectedId,
              decoration: const InputDecoration(labelText: 'Pronostiqueur'),
              items: predictors
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value.first.predictorName),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedPredictorId = value);
                }
              },
            ),
            const SizedBox(height: 10),
            ...selected.map(
              (item) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(item.playerName),
                subtitle: Text(_categoryLabel(item.category)),
                trailing: Text('${item.value}'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _categoryLabel(String category) {
    return switch (category) {
      'buts' => 'Buts',
      'passes' => 'Passes décisives',
      'hommes_du_match' => 'Hommes du match',
      'clean_sheets' => 'Clean sheets',
      'penalty_faults' => 'Fautes provoquant un penalty',
      _ => category,
    };
  }
}

class _PredictionCard extends ConsumerWidget {
  const _PredictionCard({required this.item, required this.isSaving});

  final MatchPredictionItem item;
  final bool isSaving;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(predictionsControllerProvider.notifier);
    final status = item.isClosed
        ? 'Fermé à H-5'
        : item.isFilled
            ? 'Enregistré'
            : 'À saisir';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'AS Grinta – ${item.opponentName}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text(status)),
              ],
            ),
            Text(AppFormats.dateTime(item.kickoffAt)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _Odds(label: '1', value: item.oddsWin)),
                const SizedBox(width: 8),
                Expanded(child: _Odds(label: 'N', value: item.oddsDraw)),
                const SizedBox(width: 8),
                Expanded(child: _Odds(label: '2', value: item.oddsLoss)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ScoreSelector(
                  label: 'AS Grinta',
                  value: item.scoreGrinta,
                  enabled: item.canEdit && !isSaving,
                  onMinus: () => controller.changeScore(
                    matchId: item.matchId,
                    grinta: true,
                    delta: -1,
                  ),
                  onPlus: () => controller.changeScore(
                    matchId: item.matchId,
                    grinta: true,
                    delta: 1,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('–'),
                ),
                _ScoreSelector(
                  label: item.opponentName,
                  value: item.scoreOpponent,
                  enabled: item.canEdit && !isSaving,
                  onMinus: () => controller.changeScore(
                    matchId: item.matchId,
                    grinta: false,
                    delta: -1,
                  ),
                  onPlus: () => controller.changeScore(
                    matchId: item.matchId,
                    grinta: false,
                    delta: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (item.isClosed)
              const Text(
                'Les pronostics sont verrouillés cinq minutes avant le coup d’envoi.',
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isSaving ? null : () => controller.save(item.matchId),
                  icon: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Enregistrer'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScoreSelector extends StatelessWidget {
  const _ScoreSelector({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final int value;
  final bool enabled;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: enabled && value > 0 ? onMinus : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$value', style: Theme.of(context).textTheme.headlineSmall),
              IconButton(
                onPressed: enabled ? onPlus : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Odds extends StatelessWidget {
  const _Odds({required this.label, required this.value});

  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final formatted = value == null
        ? '—'
        : value!.toStringAsFixed(2).replaceAll('.', ',');
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(label),
          Text(formatted, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({required this.entries});

  final List<LeaderboardEntry> entries;

  String _format(double value) {
    if ((value - value.round()).abs() < 0.000001) return '${value.round()}';
    return value.toStringAsFixed(1).replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...entries]
      ..sort((a, b) => b.totalPoints.compareTo(a.totalPoints));
    if (sorted.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Aucun point calculable.'),
        ),
      );
    }
    return Card(
      child: Column(
        children: sorted.indexed
            .map(
              (entry) => ListTile(
                leading: CircleAvatar(child: Text('${entry.$1 + 1}')),
                title: Text(entry.$2.name),
                subtitle: Text(
                  'Match ${_format(entry.$2.matchPoints)} · Saison ${_format(entry.$2.seasonPoints)}',
                ),
                trailing: Text(
                  _format(entry.$2.totalPoints),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(message),
      ),
    );
  }
}
