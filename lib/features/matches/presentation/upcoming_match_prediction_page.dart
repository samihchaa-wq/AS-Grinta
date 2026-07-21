import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/matches/presentation/widgets/match_result_score_chip.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/match_availability_selector.dart';
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
    final prediction = ref.watch(
      matchPredictionDetailsProvider(widget.matchId),
    );
    final details = ref.watch(matchDetailsProvider(widget.matchId));

    return Scaffold(
      appBar: GrintaAppBar(title: const SizedBox.shrink()),
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

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                child: _BetCard(
                  item: item,
                  details: details,
                  scoreGrinta: _grinta ?? item.scoreGrinta,
                  scoreOpponent: _opponent ?? item.scoreOpponent,
                  useX2: _useX2 ?? item.useX2,
                  saving: _saving,
                  onGrintaMinus: () => setState(() {
                    final current = _grinta ?? item.scoreGrinta;
                    if (current > 0) _grinta = current - 1;
                  }),
                  onGrintaPlus: () => setState(() {
                    _grinta = (_grinta ?? item.scoreGrinta) + 1;
                  }),
                  onOpponentMinus: () => setState(() {
                    final current = _opponent ?? item.scoreOpponent;
                    if (current > 0) _opponent = current - 1;
                  }),
                  onOpponentPlus: () => setState(() {
                    _opponent = (_opponent ?? item.scoreOpponent) + 1;
                  }),
                  onX2Changed: (value) => setState(() => _useX2 = value),
                  onSave: () => _save(item),
                ),
              ),
            ),
          );
        },
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Pronostic enregistré.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _BetCard extends StatelessWidget {
  const _BetCard({
    required this.item,
    required this.details,
    required this.scoreGrinta,
    required this.scoreOpponent,
    required this.useX2,
    required this.saving,
    required this.onGrintaMinus,
    required this.onGrintaPlus,
    required this.onOpponentMinus,
    required this.onOpponentPlus,
    required this.onX2Changed,
    required this.onSave,
  });

  final MatchPredictionItem item;
  final AsyncValue<MatchDetailsData> details;
  final int scoreGrinta;
  final int scoreOpponent;
  final bool useX2;
  final bool saving;
  final VoidCallback onGrintaMinus;
  final VoidCallback onGrintaPlus;
  final VoidCallback onOpponentMinus;
  final VoidCallback onOpponentPlus;
  final ValueChanged<bool> onX2Changed;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final canEdit = item.canEdit && !saving;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TeamsRow(item: item),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          MatchAvailabilitySelector(matchId: item.matchId, bottomSpacing: 12),
          details.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
            data: (data) => _HistoryStrip(details: data),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text(
            'Score à modifier',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ScorePicker(
                  label: 'AS Grinta',
                  value: scoreGrinta,
                  enabled: canEdit,
                  onMinus: onGrintaMinus,
                  onPlus: onGrintaPlus,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '–',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              Expanded(
                child: _ScorePicker(
                  label: item.opponentName,
                  value: scoreOpponent,
                  enabled: canEdit,
                  onMinus: onOpponentMinus,
                  onPlus: onOpponentPlus,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              final odds = _OddsSection(
                item: item,
                scoreGrinta: scoreGrinta,
                scoreOpponent: scoreOpponent,
              );
              final x2 = _X2Section(
                useX2: useX2,
                available: item.x2Available,
                enabled: !item.isClosed && !saving,
                onChanged: onX2Changed,
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [odds, const SizedBox(height: 10), x2],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: odds),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: x2),
                ],
              );
            },
          ),
          if (!item.isClosed) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: saving ? null : onSave,
                icon: saving
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
          const SizedBox(height: 6),
          Text(
            item.isClosed
                ? 'Pronostics fermés'
                : 'Modifiable jusqu’à 5 minutes avant le coup d’envoi',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _TeamsRow extends StatelessWidget {
  const _TeamsRow({required this.item});

  final MatchPredictionItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _TeamName(label: 'AS Grinta')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '–',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
            ),
            Expanded(child: _TeamName(label: item.opponentName)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          AppFormats.dateTime(item.kickoffAt),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

class _TeamName extends StatelessWidget {
  const _TeamName({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontSize: 22,
            height: 1.05,
            fontWeight: FontWeight.w800,
          ),
    );
  }
}

class _HistoryStrip extends StatelessWidget {
  const _HistoryStrip({required this.details});

  final MatchDetailsData details;

  @override
  Widget build(BuildContext context) {
    final matches = details.headToHead.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Les 5 dernières rencontres',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (matches.isEmpty)
          Text(
            'Aucune confrontation précédente.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: matches
                .map(
                  (match) => MatchResultScoreChip(
                    scoreGrinta: match.scoreGrinta ?? 0,
                    scoreOpponent: match.scoreOpponent ?? 0,
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}

class _OddsSection extends StatelessWidget {
  const _OddsSection({
    required this.item,
    required this.scoreGrinta,
    required this.scoreOpponent,
  });

  final MatchPredictionItem item;
  final int scoreGrinta;
  final int scoreOpponent;

  @override
  Widget build(BuildContext context) {
    final grintaWins = scoreGrinta > scoreOpponent;
    final draw = scoreGrinta == scoreOpponent;
    final opponentWins = scoreGrinta < scoreOpponent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Les cotes',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _Odd(
                label: '1',
                value: AppFormats.odds(item.oddsWin),
                active: grintaWins,
                activeColor: const Color(0xFF39E784),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _Odd(
                label: 'N',
                value: AppFormats.odds(item.oddsDraw),
                active: draw,
                activeColor: const Color(0xFFFFA726),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _Odd(
                label: '2',
                value: AppFormats.odds(item.oddsLoss),
                active: opponentWins,
                activeColor: const Color(0xFFFF5F74),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _X2Section extends StatelessWidget {
  const _X2Section({
    required this.useX2,
    required this.available,
    required this.enabled,
    required this.onChanged,
  });

  final bool useX2;
  final int available;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt_rounded, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Activer le ×2',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  '$available en réserve',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          Switch(
            value: useX2,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: enabled && (useX2 || available > 0) ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

class _Odd extends StatelessWidget {
  const _Odd({
    required this.label,
    required this.value,
    required this.active,
    required this.activeColor,
  });

  final String label;
  final String value;
  final bool active;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final inactiveBorder = Theme.of(context).colorScheme.outlineVariant;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: active ? activeColor.withValues(alpha: .13) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active ? activeColor : inactiveBorder,
          width: active ? 1.8 : 1,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: activeColor.withValues(alpha: .28),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : const [],
      ),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: active ? activeColor : AppTheme.textSecondary,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w400,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: active ? activeColor : null,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
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
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: enabled && value > 0 ? onMinus : null,
              icon: const Icon(Icons.remove_circle_outline, size: 22),
            ),
            SizedBox(
              width: 38,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: enabled ? onPlus : null,
              icon: const Icon(Icons.add_circle_outline, size: 22),
            ),
          ],
        ),
      ],
    );
  }
}
