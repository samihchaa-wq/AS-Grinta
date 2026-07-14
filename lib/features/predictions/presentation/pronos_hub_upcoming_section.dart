part of 'pronos_hub_page.dart';

class _UpcomingPredictionCard extends ConsumerWidget {
  const _UpcomingPredictionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(predictionsControllerProvider);
    if (state.isLoading) return const _LoadingCard();
    if (state.items.isEmpty) {
      return const _MessageCard(message: 'Aucun match à pronostiquer.');
    }

    final item = state.items.first;
    final details = ref.watch(matchDetailsProvider(item.matchId));
    final isSaving = state.savingMatchId == item.matchId;
    final controller = ref.read(predictionsControllerProvider.notifier);

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BetStatusHeader(item: item),
          const SizedBox(height: 20),
          _TeamsAndKickoff(item: item),
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
            data: (data) => _CompactHeadToHead(data: data),
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
                child: _ScoreColumn(
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
              ),
              Text('–', style: Theme.of(context).textTheme.headlineMedium),
              Expanded(
                child: _ScoreColumn(
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
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 20),
          _OddsAndX2(
            item: item,
            isSaving: isSaving,
            onToggleX2: () => controller.toggleX2(item.matchId),
          ),
          if (!item.isClosed) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: !item.canEdit || isSaving
                    ? null
                    : () async {
                        await controller.save(item.matchId);
                        ref.invalidate(homeDashboardProvider);
                      },
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

class _BetStatusHeader extends StatelessWidget {
  const _BetStatusHeader({required this.item});

  final MatchPredictionItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Ton pari',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.3,
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

class _TeamsAndKickoff extends StatelessWidget {
  const _TeamsAndKickoff({required this.item});

  final MatchPredictionItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _TeamLabel(label: 'AS Grinta')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '–',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
            ),
            Expanded(child: _TeamLabel(label: item.opponentName)),
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

class _TeamLabel extends StatelessWidget {
  const _TeamLabel({required this.label});

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

class _CompactHeadToHead extends StatelessWidget {
  const _CompactHeadToHead({required this.data});

  final MatchDetailsData data;

  @override
  Widget build(BuildContext context) {
    final matches = data.headToHead.take(5).toList();

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
              final color = grinta > opponent
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
                        color: color,
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

class _OddsAndX2 extends StatelessWidget {
  const _OddsAndX2({
    required this.item,
    required this.isSaving,
    required this.onToggleX2,
  });

  final MatchPredictionItem item;
  final bool isSaving;
  final VoidCallback onToggleX2;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final odds = Column(
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
                  child: _OddTile(
                    label: '1',
                    value: AppFormats.odds(item.oddsWin),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _OddTile(
                    label: 'N',
                    value: AppFormats.odds(item.oddsDraw),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _OddTile(
                    label: '2',
                    value: AppFormats.odds(item.oddsLoss),
                  ),
                ),
              ],
            ),
          ],
        );

        final x2 = Container(
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
                      '${item.x2Available} en réserve',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: item.useX2,
                onChanged:
                    (!item.useX2 && item.x2Available <= 0) || isSaving
                        ? null
                        : (_) => onToggleX2(),
              ),
            ],
          ),
        );

        if (constraints.maxWidth < 560) {
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
    );
  }
}
