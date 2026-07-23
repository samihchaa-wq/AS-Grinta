import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/matches/presentation/widgets/match_result_score_chip.dart';
import 'package:as_grinta/features/predictions/data/predictions_repository.dart';
import 'package:as_grinta/features/predictions/presentation/predictions_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final inlineMatchPredictionProvider = FutureProvider.autoDispose
    .family<MatchPredictionItem?, String>((ref, matchId) {
  return ref.watch(predictionsRepositoryProvider).fetchMatchPrediction(matchId);
});

class InlineMatchPredictionCard extends ConsumerStatefulWidget {
  const InlineMatchPredictionCard({
    super.key,
    required this.matchId,
  });

  final String matchId;

  @override
  ConsumerState<InlineMatchPredictionCard> createState() =>
      _InlineMatchPredictionCardState();
}

class _InlineMatchPredictionCardState
    extends ConsumerState<InlineMatchPredictionCard> {
  int? _scoreGrinta;
  int? _scoreOpponent;
  bool? _useX2;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final prediction = ref.watch(inlineMatchPredictionProvider(widget.matchId));
    final details = ref.watch(matchDetailsProvider(widget.matchId));

    return prediction.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text('$error'),
        ),
      ),
      data: (item) {
        if (item == null) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('Ce match est introuvable.'),
            ),
          );
        }

        _scoreGrinta ??= item.scoreGrinta;
        _scoreOpponent ??= item.scoreOpponent;
        _useX2 ??= item.useX2;

        final grinta = _scoreGrinta ?? item.scoreGrinta;
        final opponent = _scoreOpponent ?? item.scoreOpponent;
        final useX2 = _useX2 ?? item.useX2;
        final canEdit = item.canEdit && !_saving;

        // L'équipe qui reçoit (domicile) est affichée à gauche, comme partout
        // ailleurs dans l'app.
        final grintaNameLabel = Expanded(
          child: Text(
            'AS Grinta',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        );
        final opponentNameLabel = Expanded(
          child: Text(
            item.opponentName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        );
        final grintaPicker = Expanded(
          child: _ScorePicker(
            label: 'AS Grinta',
            value: grinta,
            enabled: canEdit,
            onMinus: () => setState(() {
              if (grinta > 0) _scoreGrinta = grinta - 1;
            }),
            onPlus: () => setState(() => _scoreGrinta = grinta + 1),
          ),
        );
        final opponentPicker = Expanded(
          child: _ScorePicker(
            label: item.opponentName,
            value: opponent,
            enabled: canEdit,
            onMinus: () => setState(() {
              if (opponent > 0) _scoreOpponent = opponent - 1;
            }),
            onPlus: () => setState(() => _scoreOpponent = opponent + 1),
          ),
        );

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF102A56),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF4B8DFF), width: 1.4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ton prono',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  _StatusChip(item: item),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  if (item.isHome) grintaNameLabel else opponentNameLabel,
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('–'),
                  ),
                  if (item.isHome) opponentNameLabel else grintaNameLabel,
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  AppFormats.dateTime(item.kickoffAt),
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 18),
              details.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const SizedBox.shrink(),
                data: (data) => _HeadToHead(data: data),
              ),
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 18),
              Text(
                'Score à modifier',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (item.isHome) grintaPicker else opponentPicker,
                  const Text('–'),
                  if (item.isHome) opponentPicker else grintaPicker,
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 18),
              Text(
                'Les cotes',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _Odd(
                      label: '1',
                      value: AppFormats.odds(item.oddsWin),
                      selected: grinta > opponent,
                      accent: const Color(0xFF39E784),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Odd(
                      label: 'N',
                      value: AppFormats.odds(item.oddsDraw),
                      selected: grinta == opponent,
                      accent: const Color(0xFFE59A1F),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Odd(
                      label: '2',
                      value: AppFormats.odds(item.oddsLoss),
                      selected: grinta < opponent,
                      accent: const Color(0xFFFF6B6B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .035),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.outline),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bolt_rounded),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Activer le ×2',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            '${item.x2Available} en réserve',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: useX2,
                      onChanged: !canEdit || (!useX2 && item.x2Available <= 0)
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
                  onPressed: canEdit ? () => _save(item) : null,
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
              const SizedBox(height: 8),
              const Text(
                'Modifiable jusqu’à 5 minutes avant le coup d’envoi',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _save(MatchPredictionItem item) async {
    setState(() => _saving = true);
    try {
      await ref.read(predictionsRepositoryProvider).savePrediction(
            matchId: item.matchId,
            scoreGrinta: _scoreGrinta ?? item.scoreGrinta,
            scoreOpponent: _scoreOpponent ?? item.scoreOpponent,
            useX2: _useX2 ?? item.useX2,
          );
      ref
        ..invalidate(inlineMatchPredictionProvider(widget.matchId))
        ..invalidate(matchDetailsProvider(widget.matchId));
      await ref.read(predictionsControllerProvider.notifier).load();
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.item});

  final MatchPredictionItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: item.isFilled
            ? const Color(0xFF39E784).withValues(alpha: .10)
            : Colors.white.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: item.isFilled
              ? const Color(0xFF39E784).withValues(alpha: .34)
              : AppTheme.outline,
        ),
      ),
      child: Text(
        item.isFilled ? 'Enregistré' : 'À saisir',
        style: TextStyle(
          color:
              item.isFilled ? const Color(0xFF69E99B) : AppTheme.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HeadToHead extends StatelessWidget {
  const _HeadToHead({required this.data});

  final MatchDetailsData data;

  @override
  Widget build(BuildContext context) {
    final matches = data.headToHead.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Les 5 dernières rencontres',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        if (matches.isEmpty)
          const Text(
            'Aucune confrontation précédente.',
            style: TextStyle(color: AppTheme.textSecondary),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: matches.map((match) {
              return MatchResultScoreChip(
                scoreGrinta: match.scoreGrinta ?? 0,
                scoreOpponent: match.scoreOpponent ?? 0,
              );
            }).toList(),
          ),
      ],
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
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: enabled && value > 0 ? onMinus : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text(
              '$value',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
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

class _Odd extends StatelessWidget {
  const _Odd({
    required this.label,
    required this.value,
    required this.selected,
    required this.accent,
  });

  final String label;
  final String value;
  final bool selected;

  /// Couleur du résultat (1 vert, N orange, 2 rouge), appliquée à la
  /// sélection.
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: selected ? accent.withValues(alpha: .16) : null,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? accent : AppTheme.outline,
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: selected ? accent : null,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: selected ? accent : null,
            ),
          ),
        ],
      ),
    );
  }
}
