import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/matches/presentation/widgets/match_result_score_chip.dart';
import 'package:as_grinta/features/predictions/data/predictions_repository.dart';
import 'package:as_grinta/features/predictions/presentation/predictions_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';

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
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final prediction = ref.watch(inlineMatchPredictionProvider(widget.matchId));
    final details = ref.watch(matchDetailsProvider(widget.matchId));

    return prediction.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.cardPadding),
          child: Center(child: GrintaProgressIndicator()),
        ),
      ),
      error: (error, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Text(humanizeError(error)),
        ),
      ),
      data: (item) {
        if (item == null) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.cardPadding),
              child: Text('Ce match est introuvable.'),
            ),
          );
        }

        _scoreGrinta ??= item.scoreGrinta;
        _scoreOpponent ??= item.scoreOpponent;

        final grinta = _scoreGrinta ?? item.scoreGrinta;
        final opponent = _scoreOpponent ?? item.scoreOpponent;
        final now = DateTime.now();
        final notOpenYet = now.isBefore(item.opensAt);
        final closed = !notOpenYet && !item.canEditAt(now);
        final canEdit = !notOpenYet && !closed && !_saving;

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
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          decoration: BoxDecoration(
            color: const Color(0xFF102A56),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF4B8DFF), width: 1.4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: _StatusChip(
                  item: item,
                  notOpenYet: notOpenYet,
                  closed: closed,
                ),
              ),
              const SizedBox(height: AppSpacing.contentGap),
              details.when(
                loading: () => const Center(
                  child: SizedBox.square(
                    dimension: 24,
                    child: GrintaProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (_, __) => const Text(
                  'Historique des confrontations momentanément indisponible.',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                data: (data) => _HeadToHead(data: data),
              ),
              const SizedBox(height: AppSpacing.sectionGap),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.sectionGap),
              Text(
                'Score à modifier',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: AppSpacing.contentGap),
              Row(
                children: [
                  if (item.isHome) grintaPicker else opponentPicker,
                  const Text('–'),
                  if (item.isHome) opponentPicker else grintaPicker,
                ],
              ),
              const SizedBox(height: AppSpacing.sectionGap),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.sectionGap),
              Text(
                'Les cotes',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: AppSpacing.contentGap),
              Row(
                children: [
                  Expanded(
                    child: _Odd(
                      label: '1',
                      value: AppFormats.odds(
                        item.isHome ? item.oddsWin : item.oddsLoss,
                      ),
                      selected:
                          item.isHome ? grinta > opponent : opponent > grinta,
                      accent: const Color(0xFF39E784),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.contentGap),
                  Expanded(
                    child: _Odd(
                      label: 'N',
                      value: AppFormats.odds(item.oddsDraw),
                      selected: grinta == opponent,
                      accent: const Color(0xFFE59A1F),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.contentGap),
                  Expanded(
                    child: _Odd(
                      label: '2',
                      value: AppFormats.odds(
                        item.isHome ? item.oddsLoss : item.oddsWin,
                      ),
                      selected:
                          item.isHome ? grinta < opponent : opponent < grinta,
                      accent: const Color(0xFFFF6B6B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sectionGap),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: canEdit ? () => _save(item) : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: GrintaProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Enregistrer'),
                ),
              ),
              const SizedBox(height: AppSpacing.contentGap),
              Text(
                notOpenYet
                    ? 'Disponible à partir de J−6 à 12 h, heure de Paris.'
                    : closed
                        ? 'Pronostic fermé 5 minutes avant le coup d’envoi.'
                        : 'Modifiable jusqu’à 5 minutes avant le coup d’envoi.',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
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
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.item,
    required this.notOpenYet,
    required this.closed,
  });

  final MatchPredictionItem item;
  final bool notOpenYet;
  final bool closed;

  @override
  Widget build(BuildContext context) {
    final saved = item.isFilled;
    final label = notOpenYet
        ? 'Pas encore ouvert'
        : closed
            ? 'Fermé'
            : saved
                ? 'Enregistré'
                : 'À saisir';
    final highlighted = saved && !notOpenYet && !closed;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.compactCardPadding,
        vertical: AppSpacing.contentGap,
      ),
      decoration: BoxDecoration(
        color: highlighted
            ? const Color(0xFF39E784).withValues(alpha: .10)
            : Colors.white.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: highlighted
              ? const Color(0xFF39E784).withValues(alpha: .34)
              : AppTheme.outline,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: highlighted
              ? const Color(0xFF69E99B)
              : AppTheme.textSecondary,
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
        const SizedBox(height: AppSpacing.contentGap),
        if (matches.isEmpty)
          const Text(
            'Aucune confrontation précédente.',
            style: TextStyle(color: AppTheme.textSecondary),
          )
        else
          Wrap(
            spacing: AppSpacing.contentGap,
            runSpacing: AppSpacing.contentGap,
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
      mainAxisSize: MainAxisSize.min,
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
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              padding: EdgeInsets.zero,
              onPressed: enabled && value > 0 ? onMinus : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text(
              '$value',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              padding: EdgeInsets.zero,
              onPressed: enabled && value < 99 ? onPlus : null,
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
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.contentGap),
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
