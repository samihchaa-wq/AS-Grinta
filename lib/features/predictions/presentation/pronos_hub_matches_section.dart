part of 'pronos_hub_page.dart';

class _MatchesSection extends ConsumerStatefulWidget {
  const _MatchesSection();

  @override
  ConsumerState<_MatchesSection> createState() => _MatchesSectionState();
}

class _MatchesSectionState extends ConsumerState<_MatchesSection> {
  _MatchView _view = _MatchView.upcoming;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(predictionsControllerProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<_MatchView>(
              segments: const [
                ButtonSegment(
                  value: _MatchView.upcoming,
                  icon: Icon(Icons.bolt_rounded),
                  label: Text('Prochain prono'),
                ),
                ButtonSegment(
                  value: _MatchView.ranking,
                  icon: Icon(Icons.leaderboard_outlined),
                  label: Text('Classement'),
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
            _MatchView.upcoming => const _UpcomingMatchView(),
            _MatchView.ranking => const _MatchRankingView(),
          },
        ),
      ],
    );
  }
}

class _UpcomingMatchView extends ConsumerWidget {
  const _UpcomingMatchView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(homeDashboardProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(homeDashboardProvider);
        await Future.wait([
          ref.read(predictionsControllerProvider.notifier).load(),
          ref.read(homeDashboardProvider.future),
        ]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
        children: [
          dashboard.when(
            loading: () => const _LoadingCard(),
            error: (_, __) => const _MessageCard(
              message: 'Le prochain prono est indisponible.',
            ),
            data: (data) => _UpcomingPredictionCard(
              participantCount: data.predictionParticipantCount,
            ),
          ),
        ],
      ),
    );
  }
}
