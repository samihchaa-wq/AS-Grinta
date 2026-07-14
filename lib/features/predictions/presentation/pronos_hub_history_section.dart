part of 'pronos_hub_page.dart';

class _HistorySection extends ConsumerStatefulWidget {
  const _HistorySection();

  @override
  ConsumerState<_HistorySection> createState() => _HistorySectionState();
}

class _HistorySectionState extends ConsumerState<_HistorySection> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(matchesControllerProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchesControllerProvider);
    final matches = state.matches.where((match) => match.isFinished).toList()
      ..sort((a, b) => b.kickoffAt.compareTo(a.kickoffAt));

    return RefreshIndicator(
      onRefresh: () => ref.read(matchesControllerProvider.notifier).load(
            seasonId: state.selectedSeasonId,
          ),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
        children: [
          if (state.isLoading)
            const _LoadingCard()
          else if (state.error != null)
            _MessageCard(message: state.error!)
          else if (matches.isEmpty)
            const _MessageCard(message: 'Aucun match terminé pour le moment.')
          else
            ...matches.map(
              (match) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _HistoryMatchCard(match: match),
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryMatchCard extends StatelessWidget {
  const _HistoryMatchCard({required this.match});

  final MatchModel match;

  @override
  Widget build(BuildContext context) {
    final opponent = match.opponentName ?? 'Adversaire';
    final grintaScore = match.grintaScore ?? 0;
    final opponentScore = match.opponentScore ?? 0;
    final homeName = match.isHome ? 'AS Grinta' : opponent;
    final awayName = match.isHome ? opponent : 'AS Grinta';
    final homeScore = match.isHome ? grintaScore : opponentScore;
    final awayScore = match.isHome ? opponentScore : grintaScore;
    final result = grintaScore > opponentScore
        ? 'Victoire'
        : grintaScore == opponentScore
            ? 'Nul'
            : 'Défaite';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/matches/${match.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      homeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      '$homeScore–$awayScore',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      awayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      AppFormats.date(match.kickoffAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                  ),
                  Text(
                    result,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
