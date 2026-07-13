part of 'pronos_hub_page.dart';

class _UpcomingPredictionCard extends ConsumerWidget {
  const _UpcomingPredictionCard({required this.participantCount});

  final int participantCount;

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

    return Column(
      children: [
        _Panel(
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
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
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
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.group_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '$participantCount participant${participantCount > 1 ? 's' : ''}',
                  ),
                ],
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
              if (!item.isClosed) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: item.useX2
                        ? const Color(0xFF6A32C7).withValues(alpha: .22)
                        : Colors.white.withValues(alpha: .04),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: item.useX2
                          ? const Color(0xFF9B6CFF)
                          : Colors.white.withValues(alpha: .10),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt_rounded),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.useX2 ? '×2 activé' : 'Activer le ×2',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            Text('${item.x2Available} en réserve'),
                          ],
                        ),
                      ),
                      Switch(
                        value: item.useX2,
                        onChanged:
                            (!item.useX2 && item.x2Available <= 0) || isSaving
                                ? null
                                : (_) => controller.toggleX2(item.matchId),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
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
            ],
          ),
        ),
        const SizedBox(height: 16),
        details.when(
          loading: () => const _LoadingCard(),
          error: (_, __) => const _MessageCard(
            message: 'Les derniers face-à-face sont indisponibles.',
          ),
          data: (data) => _HeadToHeadPanel(data: data),
        ),
      ],
    );
  }
}

class _HeadToHeadPanel extends StatelessWidget {
  const _HeadToHeadPanel({required this.data});

  final MatchDetailsData data;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, color: Color(0xFF79A4FF)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Les derniers face-à-face',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Contre ${data.opponentName}',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          if (data.headToHead.isEmpty)
            const Text('Aucune confrontation précédente.')
          else
            ...data.headToHead
                .take(5)
                .map((match) => _HeadToHeadRow(match: match)),
        ],
      ),
    );
  }
}

class _HeadToHeadRow extends StatelessWidget {
  const _HeadToHeadRow({required this.match});

  final HeadToHeadMatch match;

  @override
  Widget build(BuildContext context) {
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
}
