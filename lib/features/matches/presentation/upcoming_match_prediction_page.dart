import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/predictions/data/predictions_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final matchPredictionDetailsProvider = FutureProvider.autoDispose
    .family<MatchPredictionItem?, String>((ref, matchId) {
  return ref.watch(predictionsRepositoryProvider).fetchMatchPrediction(matchId);
});

class UpcomingMatchPredictionPage extends ConsumerStatefulWidget {
  const UpcomingMatchPredictionPage({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<UpcomingMatchPredictionPage> createState() =>
      _UpcomingMatchPredictionPageState();
}

class _UpcomingMatchPredictionPageState
    extends ConsumerState<UpcomingMatchPredictionPage> {
  int? _grinta;
  int? _opponent;
  bool? _useX2;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final prediction = ref.watch(matchPredictionDetailsProvider(widget.matchId));
    final details = ref.watch(matchDetailsProvider(widget.matchId));

    return Scaffold(
      appBar: AppBar(title: const Text('Détails du match')),
      body: prediction.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (item) {
          if (item == null) {
            return const Center(child: Text('Match introuvable.'));
          }
          _grinta ??= item.scoreGrinta;
          _opponent ??= item.scoreOpponent;
          _useX2 ??= item.useX2;

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(matchPredictionDetailsProvider(widget.matchId));
              ref.invalidate(matchDetailsProvider(widget.matchId));
              await Future.wait([
                ref.read(matchPredictionDetailsProvider(widget.matchId).future),
                ref.read(matchDetailsProvider(widget.matchId).future),
              ]);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Card(
                  color: const Color(0xFF102A66),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AS Grinta – ${item.opponentName}',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(AppFormats.dateTime(item.kickoffAt)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                details.when(
                  loading: () => const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                  data: _historyCard,
                ),
                const SizedBox(height: 16),
                _predictionCard(item),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _historyCard(MatchDetailsData details) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history_rounded, color: Color(0xFF79A4FF)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '5 derniers face-à-face',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Contre ${details.opponentName}',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            if (details.headToHead.isEmpty)
              const Text('Aucune confrontation précédente.')
            else
              ...details.headToHead.map(_historyRow),
          ],
        ),
      ),
    );
  }

  Widget _historyRow(HeadToHeadMatch match) {
    final grinta = match.scoreGrinta ?? 0;
    final opponent = match.scoreOpponent ?? 0;
    final result = grinta > opponent
        ? ('V', const Color(0xFF39E784), 'Victoire')
        : grinta == opponent
            ? ('N', const Color(0xFFFFC84D), 'Nul')
            : ('D', const Color(0xFFFF6B6B), 'Défaite');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: result.$2.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              result.$1,
              style: TextStyle(
                color: result.$2,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppFormats.date(match.date)),
                Text(
                  result.$3,
                  style: TextStyle(
                    color: result.$2,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$grinta – $opponent',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _predictionCard(MatchPredictionItem item) {
    final scoreGrinta = _grinta ?? item.scoreGrinta;
    final scoreOpponent = _opponent ?? item.scoreOpponent;
    final useX2 = _useX2 ?? item.useX2;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: AppTheme.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ton pronostic',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      item.isClosed
                          ? 'Pronostics fermés'
                          : 'Modifiable jusqu’à 5 minutes avant le coup d’envoi',
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              Chip(
                label: Text(
                  item.isClosed
                      ? 'Fermés'
                      : item.isFilled
                          ? 'Enregistré'
                          : 'À saisir',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _Odd(label: '1', value: AppFormats.odds(item.oddsWin))),
              const SizedBox(width: 8),
              Expanded(child: _Odd(label: 'N', value: AppFormats.odds(item.oddsDraw))),
              const SizedBox(width: 8),
              Expanded(child: _Odd(label: '2', value: AppFormats.odds(item.oddsLoss))),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _ScorePicker(
                  label: 'AS Grinta',
                  value: scoreGrinta,
                  enabled: item.canEdit && !_saving,
                  onMinus: () => setState(() => _grinta = scoreGrinta - 1),
                  onPlus: () => setState(() => _grinta = scoreGrinta + 1),
                ),
              ),
              const Text('–', style: TextStyle(fontSize: 28)),
              Expanded(
                child: _ScorePicker(
                  label: item.opponentName,
                  value: scoreOpponent,
                  enabled: item.canEdit && !_saving,
                  onMinus: () => setState(() => _opponent = scoreOpponent - 1),
                  onPlus: () => setState(() => _opponent = scoreOpponent + 1),
                ),
              ),
            ],
          ),
          if (!item.isClosed) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: useX2
                    ? const Color(0xFF6A32C7).withValues(alpha: .22)
                    : Colors.white.withValues(alpha: .04),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      useX2
                          ? '×2 activé · ${item.x2Available} en réserve'
                          : 'Activer le ×2 · ${item.x2Available} en réserve',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Switch(
                    value: useX2,
                    onChanged: (!useX2 && item.x2Available <= 0) || _saving
                        ? null
                        : (value) => setState(() => _useX2 = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : () => _save(item),
                icon: _saving
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
        ],
      ),
    );
  }

  Future<void> _save(MatchPredictionItem item) async {
    setState(() => _saving = true);
    try {
      await ref.read(predictionsRepositoryProvider).savePrediction(
            matchId: item.matchId,
            scoreGrinta: _grinta ?? item.scoreGrinta,
            scoreOpponent: _opponent ?? item.scoreOpponent,
            useX2: _useX2 ?? item.useX2,
          );
      ref.invalidate(matchPredictionDetailsProvider(widget.matchId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pronostic enregistré.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _Odd extends StatelessWidget {
  const _Odd({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(children: [Text(label), Text(value)]),
    );
  }
}

class _ScorePicker extends StatelessWidget {
  const _ScorePicker({
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
    return Column(
      children: [
        Text(label, maxLines: 2, textAlign: TextAlign.center),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: enabled && value > 0 ? onMinus : null,
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
    );
  }
}
