import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/predictions/data/predictions_repository.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
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
      appBar: GrintaAppBar(title: const Text('Ton pari')),
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
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    _BetHeader(item: item),
                    const SizedBox(height: 16),
                    _BetCard(
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
                  ],
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pronostic enregistré.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _BetHeader extends StatelessWidget {
  const _BetHeader({required this.item});

  final MatchPredictionItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Ton pari',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.4,
                ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
            item.isClosed
                ? 'Fermé'
                : item.isFilled
                    ? 'Enregistré'
                    : 'À saisir',
            style: TextStyle(
              color: item.isFilled
                  ? const Color(0xFF69E99B)
                  : AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TeamsRow(item: item),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 20),
          details.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
            data: (data) => _HistoryStrip(details: data),
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 20),
          Text(
            'Score à modifier',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 14),
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
                padding: const EdgeInsets.symmetric(horizontal: 8),
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
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              final odds = _OddsSection(item: item);
              final x2 = _X2Section(
                useX2: useX2,
                available: item.x2Available,
                enabled: !item.isClosed && !saving,
                onChanged: onX2Changed,
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    odds,
                    const SizedBox(height: 16),
                    x2,
                  ],
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
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
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
          const SizedBox(height: 10),
          Text(
            item.isClosed
                ? 'Pronostics fermés'
                : 'Modifiable jusqu’à 5 minutes avant le coup d’envoi',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
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
              padding: const EdgeInsets.symmetric(horizontal: 12),
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
        const SizedBox(height: 10),
        Text(
          AppFormats.dateTime(item.kickoffAt),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
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
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 12),
        if (matches.isEmpty)
          Text(
            'Aucune confrontation précédente.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: matches.map((match) {
              final grinta = match.scoreGrinta ?? 0;
              final opponent = match.scoreOpponent ?? 0;
              final result = grinta > opponent
                  ? const Color(0xFF39E784)
                  : grinta == opponent
                      ? const Color(0xFFFFC84D)
                      : const Color(0xFFFF6B6B);

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .035),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.outline),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$grinta–$opponent',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: result,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

class _OddsSection extends StatelessWidget {
  const _OddsSection({required this.item});

  final MatchPredictionItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Les cotes',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Odd(label: '1', value: AppFormats.odds(item.oddsWin)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Odd(label: 'N', value: AppFormats.odds(item.oddsDraw)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Odd(label: '2', value: AppFormats.odds(item.oddsLoss)),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt_rounded, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Activer le ×2',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
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
            onChanged: enabled && (useX2 || available > 0) ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

class _Odd extends StatelessWidget {
  const _Odd({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
              ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: enabled && value > 0 ? onMinus : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(
              width: 42,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
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
