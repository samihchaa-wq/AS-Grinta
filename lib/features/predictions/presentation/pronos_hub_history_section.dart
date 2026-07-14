part of 'pronos_hub_page.dart';

class _CalendarSection extends ConsumerStatefulWidget {
  const _CalendarSection();

  @override
  ConsumerState<_CalendarSection> createState() => _CalendarSectionState();
}

class _CalendarSectionState extends ConsumerState<_CalendarSection> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await Future.wait([
        ref.read(matchesControllerProvider.notifier).load(),
        ref.read(predictionsControllerProvider.notifier).load(),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchesControllerProvider);
    final predictionState = ref.watch(predictionsControllerProvider);
    final isAdmin =
        ref.watch(authControllerProvider).profile?.role == AuthRole.admin;
    final matches = [...state.matches]
      ..sort((a, b) => b.kickoffAt.compareTo(a.kickoffAt));
    final nextPredictionMatchId = predictionState.items.isEmpty
        ? null
        : predictionState.items.first.matchId;

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          ref.read(matchesControllerProvider.notifier).load(
                seasonId: state.selectedSeasonId,
              ),
          ref.read(predictionsControllerProvider.notifier).load(),
        ]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          if (state.isLoading)
            const _LoadingCard()
          else if (state.error != null)
            _MessageCard(message: state.error!)
          else if (matches.isEmpty)
            const _MessageCard(message: 'Aucun match pour le moment.')
          else
            ...matches.map(
              (match) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: !match.isFinished && match.id == nextPredictionMatchId
                    ? _UpcomingPredictionCard(
                        onEnterStats: isAdmin
                            ? () => context.push(
                                  '/matches/${match.id}/finalize',
                                )
                            : null,
                      )
                    : _CalendarMatchCard(
                        match: match,
                        isAdmin: isAdmin,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CalendarMatchCard extends StatelessWidget {
  const _CalendarMatchCard({required this.match, required this.isAdmin});

  final MatchModel match;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final opponent = match.opponentName ?? 'Adversaire';
    final grintaScore = match.grintaScore ?? 0;
    final opponentScore = match.opponentScore ?? 0;
    final homeName = match.isHome ? 'AS Grinta' : opponent;
    final awayName = match.isHome ? opponent : 'AS Grinta';
    final homeScore = match.isHome ? grintaScore : opponentScore;
    final awayScore = match.isHome ? opponentScore : grintaScore;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/matches/${match.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      match.isFinished
                          ? '$homeName $homeScore–$awayScore $awayName'
                          : '$homeName – $awayName',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    match.isFinished ? 'Terminé' : 'À venir',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                AppFormats.dateTime(match.kickoffAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
              if (isAdmin) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () =>
                        context.push('/matches/${match.id}/finalize'),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(
                      match.isFinished
                          ? 'Changer les stats'
                          : 'Entrer les stats',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
