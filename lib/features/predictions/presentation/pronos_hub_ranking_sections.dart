part of 'pronos_hub_page.dart';

class _MatchRankingView extends ConsumerWidget {
  const _MatchRankingView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaderboard = ref.watch(leaderboardProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(leaderboardProvider);
        await ref.read(leaderboardProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
        children: [
          leaderboard.when(
            loading: () => const _LoadingCard(),
            error: (_, __) => const _MessageCard(
              message: 'Le classement des matchs est indisponible.',
            ),
            data: (entries) => _LeaderboardCard(
              entries: entries,
              points: (entry) => entry.matchPoints * 100,
              showMatchStats: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _GeneralSection extends ConsumerWidget {
  const _GeneralSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaderboard = ref.watch(leaderboardProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(leaderboardProvider);
        await ref.read(leaderboardProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
        children: [
          Text(
            'Classement général',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text('Classement combiné des matchs et de la saison.'),
          const SizedBox(height: 14),
          leaderboard.when(
            loading: () => const _LoadingCard(),
            error: (_, __) => const _MessageCard(
              message: 'Le classement général est indisponible.',
            ),
            data: (entries) => _LeaderboardCard(
              entries: entries,
              points: (entry) => entry.totalPoints.roundToDouble(),
            ),
          ),
        ],
      ),
    );
  }
}
