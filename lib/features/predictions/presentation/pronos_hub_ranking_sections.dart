part of 'pronos_hub_page.dart';

class _GeneralRankingsSection extends StatefulWidget {
  const _GeneralRankingsSection({this.initialView});

  final String? initialView;

  @override
  State<_GeneralRankingsSection> createState() =>
      _GeneralRankingsSectionState();
}

class _GeneralRankingsSectionState extends State<_GeneralRankingsSection> {
  late _GeneralRankingView _view = switch (widget.initialView) {
    'scorers' => _GeneralRankingView.scorers,
    'general' => _GeneralRankingView.general,
    _ => _GeneralRankingView.matches,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<_GeneralRankingView>(
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(
                  value: _GeneralRankingView.matches,
                  label: Text('Matchs'),
                ),
                ButtonSegment(
                  value: _GeneralRankingView.scorers,
                  label: Text('Buteurs'),
                ),
                ButtonSegment(
                  value: _GeneralRankingView.general,
                  label: Text('Général'),
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
            _GeneralRankingView.matches => const _MatchRankingView(),
            _GeneralRankingView.scorers => const _ScorerRankingView(),
            _GeneralRankingView.general => const _GeneralRankingViewWidget(),
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

class _ScorerRankingView extends StatelessWidget {
  const _ScorerRankingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
      children: const [SeasonRankingPanel()],
    );
  }
}

class _GeneralRankingViewWidget extends ConsumerWidget {
  const _GeneralRankingViewWidget();

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
