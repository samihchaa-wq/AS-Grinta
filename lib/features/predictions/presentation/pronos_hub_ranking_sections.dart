part of 'pronos_hub_page.dart';

class _RankingsSection extends StatefulWidget {
  const _RankingsSection();

  @override
  State<_RankingsSection> createState() => _RankingsSectionState();
}

class _RankingsSectionState extends State<_RankingsSection> {
  _RankingView _view = _RankingView.matches;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<_RankingView>(
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size.fromHeight(54)),
                textStyle: WidgetStatePropertyAll(
                  TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(
                  value: _RankingView.matches,
                  label: Text('Matchs'),
                ),
                ButtonSegment(
                  value: _RankingView.season,
                  label: Text('Buteur'),
                ),
                ButtonSegment(
                  value: _RankingView.general,
                  label: Text('Cumulé'),
                ),
              ],
              selected: {_view},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                setState(() => _view = selection.first);
              },
            ),
          ),
        ),
        Expanded(
          child: switch (_view) {
            _RankingView.matches => const _MatchRankingView(),
            _RankingView.season => const _SeasonRankingView(),
            _RankingView.general => const _GeneralSection(),
          },
        ),
      ],
    );
  }
}

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

class _SeasonRankingView extends StatelessWidget {
  const _SeasonRankingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
      children: const [SeasonRankingPanel()],
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
          const Text('2/3 matchs · 1/3 saison.'),
          const SizedBox(height: 14),
          leaderboard.when(
            loading: () => const _LoadingCard(),
            error: (_, __) => const _MessageCard(
              message: 'Le classement cumulé est indisponible.',
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
