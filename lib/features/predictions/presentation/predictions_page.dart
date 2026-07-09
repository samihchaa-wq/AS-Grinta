import 'package:as_grinta/features/predictions/data/predictions_repository.dart';
import 'package:as_grinta/features/predictions/presentation/predictions_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class PredictionsPage extends ConsumerStatefulWidget {
  const PredictionsPage({super.key});

  @override
  ConsumerState<PredictionsPage> createState() => _PredictionsPageState();
}

class _PredictionsPageState extends ConsumerState<PredictionsPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(predictionsControllerProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(predictionsControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pronostics de match'),
        actions: [
          IconButton(
            tooltip: 'Classement général',
            onPressed: () => context.push('/predictions/leaderboard'),
            icon: const Icon(Icons.leaderboard_outlined),
          ),
          IconButton(
            tooltip: 'Pronostics de saison',
            onPressed: () => context.push('/predictions/season'),
            icon: const Icon(Icons.emoji_events_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(predictionsControllerProvider.notifier).load(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.leaderboard_outlined),
                    title: const Text('Classement général'),
                    subtitle: const Text(
                      'Somme directe des points de match et de saison.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/predictions/leaderboard'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.emoji_events_outlined),
                    title: const Text('Pronostics de saison'),
                    subtitle: const Text(
                      'Buts, passes, hommes du match et clean sheets.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/predictions/season'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (state.error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    state.error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ),
            if (state.isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Aucun match disponible pour les pronostics.'),
                ),
              )
            else
              ...state.items.map(
                (item) => _PredictionCard(
                  item: item,
                  isSaving: state.savingMatchId == item.matchId,
                ),
              ),
          ],
        ),
      ),
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
    final points = item.earnedPoints;
    final statusLabel = item.isBeforeWindow
        ? 'Ouvre le ${item.opensAt.toLocal().toString().split('.').first}'
        : item.isClosed
            ? 'Fermé'
            : item.isFilled
                ? 'Enregistré'
                : 'À saisir';

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
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
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text(statusLabel)),
              ],
            ),
            const SizedBox(height: 4),
            Text(item.kickoffAt.toLocal().toString().split('.')[0]),
            if (item.oddsWin != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  Chip(label: Text('V ${item.oddsWin!.toStringAsFixed(2)}')),
                  Chip(label: Text('N ${item.oddsDraw!.toStringAsFixed(2)}')),
                  Chip(label: Text('D ${item.oddsLoss!.toStringAsFixed(2)}')),
                ],
              ),
            ],
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
                  padding: EdgeInsets.symmetric(horizontal: 18),
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
            if (item.hasResult) ...[
              const SizedBox(height: 12),
              Text(
                'Résultat : ${item.actualScoreGrinta} - ${item.actualScoreOpponent}',
              ),
              Text(
                points == null
                    ? 'Points indisponibles'
                    : 'Points gagnés : ${points.toStringAsFixed(1)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
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
        ),
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
