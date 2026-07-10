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

class _PredictionsPageState extends ConsumerState<PredictionsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String? _selectedPredictorId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    Future.microtask(
      () => ref.read(predictionsControllerProvider.notifier).load(),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
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
            tooltip: 'Mes pronostics de saison',
            onPressed: () => context.push('/predictions/season'),
            icon: const Icon(Icons.edit_calendar_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Prochain match',
              style: Theme.of(context).textTheme.titleLarge,
            ),
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
            const SizedBox(height: 22),
            Text(
              'Classements',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: 'Cumulé'),
                      Tab(text: 'Match'),
                      Tab(text: 'Saison'),
                    ],
                  ),
                  SizedBox(
                    height: 330,
                    child: leaderboardAsync.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      error: (_, __) => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Le classement est temporairement indisponible.'),
                        ),
                      ),
                      data: (entries) => TabBarView(
                        controller: _tabController,
                        children: [
                          _LeaderboardList(
                            entries: entries,
                            mode: _LeaderboardMode.total,
                          ),
                          _LeaderboardList(
                            entries: entries,
                            mode: _LeaderboardMode.match,
                          ),
                          _LeaderboardList(
                            entries: entries,
                            mode: _LeaderboardMode.season,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Pronos saison de chacun',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => context.push('/predictions/season'),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Les miens'),
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
                message: 'Les pronostics de saison sont temporairement indisponibles.',
              ),
              data: _buildSeasonPredictions,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSeasonPredictions(List<SeasonPredictionItem> items) {
    if (items.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Aucun pronostic de saison public enregistré.'),
        ),
      );
    }

    final grouped = <String, List<SeasonPredictionItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.predictorId, () => []).add(item);
    }

    final predictors = grouped.entries.toList()
      ..sort(
        (a, b) => a.value.first.predictorName
            .toLowerCase()
            .compareTo(b.value.first.predictorName.toLowerCase()),
      );

    final availableIds = predictors.map((entry) => entry.key).toSet();
    final selectedId = availableIds.contains(_selectedPredictorId)
        ? _selectedPredictorId!
        : predictors.first.key;
    final selectedItems = [...grouped[selectedId]!]
      ..sort((a, b) {
        final player = a.playerName.compareTo(b.playerName);
        if (player != 0) return player;
        return a.category.compareTo(b.category);
      });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: selectedId,
              decoration: const InputDecoration(
                labelText: 'Pronostiqueur',
                prefixIcon: Icon(Icons.person_search_outlined),
              ),
              items: predictors
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value.first.predictorName),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedPredictorId = value);
                }
              },
            ),
            const SizedBox(height: 12),
            ...selectedItems.map(
              (item) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(item.playerName),
                subtitle: Text(_categoryLabel(item.category)),
                trailing: Text(
                  '${item.value}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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
      _ => category,
    };
  }
}

enum _LeaderboardMode { total, match, season }

class _LeaderboardList extends StatelessWidget {
  const _LeaderboardList({required this.entries, required this.mode});

  final List<LeaderboardEntry> entries;
  final _LeaderboardMode mode;

  double _points(LeaderboardEntry entry) {
    return switch (mode) {
      _LeaderboardMode.total => entry.totalPoints,
      _LeaderboardMode.match => entry.matchPoints,
      _LeaderboardMode.season => entry.seasonPoints,
    };
  }

  String _formatPoints(double value) {
    if ((value - value.round()).abs() < 0.000001) return '${value.round()}';
    return value.toStringAsFixed(1).replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...entries]..sort((a, b) {
        final points = _points(b).compareTo(_points(a));
        if (points != 0) return points;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    if (sorted.isEmpty) {
      return const Center(child: Text('Aucun point calculable.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = sorted[index];
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 17,
            child: Text('${index + 1}'),
          ),
          title: Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: index == 0
                ? const TextStyle(fontWeight: FontWeight.w800)
                : null,
          ),
          trailing: SizedBox(
            width: 72,
            child: Text(
              _formatPoints(_points(entry)),
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: index == 0 ? FontWeight.w800 : FontWeight.w600,
                  ),
            ),
          ),
        );
      },
    );
  }
}

class _PredictionCard extends ConsumerWidget {
  const _PredictionCard({required this.item, required this.isSaving});

  final MatchPredictionItem item;
  final bool isSaving;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(predictionsControllerProvider.notifier);
    final statusLabel = item.isBeforeWindow
        ? 'Ouvre le ${AppFormats.dateTime(item.opensAt)}'
        : item.isClosed
            ? 'Pronostics clôturés'
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
                    'AS Grinta - ${item.opponentName}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Chip(label: Text(statusLabel)),
              ],
            ),
            const SizedBox(height: 4),
            Text(AppFormats.dateTime(item.kickoffAt)),
            if (item.oddsWin != null ||
                item.oddsDraw != null ||
                item.oddsLoss != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _OddsPoint(
                      label: '1 · Grinta',
                      odds: item.oddsWin,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _OddsPoint(
                      label: 'N · Nul',
                      odds: item.oddsDraw,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _OddsPoint(
                      label: '2 · Adverse',
                      odds: item.oddsLoss,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Points de base. Score exact : jusqu’au double.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (item.isClosed) ...[
              const SizedBox(height: 16),
              const Text(
                'La fenêtre de pronostic est fermée 10 minutes avant le coup d’envoi.',
              ),
            ] else ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ScoreEditor(
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
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('-', style: TextStyle(fontSize: 28)),
                  ),
                  _ScoreEditor(
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
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: !item.canEdit || isSaving
                      ? null
                      : () => controller.save(item.matchId),
                  icon: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Enregistrer le pronostic'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OddsPoint extends StatelessWidget {
  const _OddsPoint({required this.label, required this.odds});

  final String label;
  final double? odds;

  @override
  Widget build(BuildContext context) {
    final value = odds;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(
            value == null ? '—' : '${(value * 10).round()} pts',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _ScoreEditor extends StatelessWidget {
  const _ScoreEditor({
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
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: enabled ? onMinus : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$value', style: Theme.of(context).textTheme.headlineMedium),
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

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}
