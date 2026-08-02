part of 'pronos_hub_page.dart';

class _GeneralRankingsSection extends StatefulWidget {
  const _GeneralRankingsSection({this.initialView, this.badgeSize});

  final String? initialView;
  final double? badgeSize;

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
        GrintaSecondaryTabs<_GeneralRankingView>(
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
              label: Text('Global'),
            ),
          ],
          selected: {_view},
          onSelectionChanged: (selection) {
            setState(() => _view = selection.first);
          },
        ),
        Expanded(
          child: switch (_view) {
            _GeneralRankingView.matches => _MatchRankingView(
                badgeSize: widget.badgeSize,
              ),
            _GeneralRankingView.scorers => const ColorfulSeasonPredictionsPage(
                embedded: true,
                showRanking: false,
              ),
            _GeneralRankingView.general => _GeneralRankingViewWidget(
                badgeSize: widget.badgeSize,
              ),
          },
        ),
      ],
    );
  }
}

class _MatchRankingView extends ConsumerWidget {
  const _MatchRankingView({this.badgeSize});

  final double? badgeSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaderboard = ref.watch(leaderboardProvider);
    Future<void> refresh() async {
      ref.invalidate(leaderboardProvider);
      await ref.read(leaderboardProvider.future);
    }

    return leaderboard.when(
      loading: () => const Center(
        child: GrintaLoader.page(
          message: 'Le classement se met en place…',
          semanticLabel: 'Chargement du classement des matchs',
        ),
      ),
      error: (_, __) => const _MessageCard(
        title: 'Classement indisponible',
        icon: Icons.wifi_off_rounded,
        message: 'Le classement des matchs n\'a pas pu être chargé.',
        tone: GrintaEmptyTone.alert,
      ),
      data: (entries) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          6,
          AppSpacing.screenGutter,
          32,
        ),
        child: _LeaderboardCard(
          entries: entries,
          points: (entry) => entry.matchPoints * 100,
          showMatchStats: true,
          onRefresh: refresh,
          badgeSize: badgeSize,
        ),
      ),
    );
  }
}

class _ScorerRankingView extends ConsumerWidget {
  const _ScorerRankingView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> refresh() async {
      ref.invalidate(leaderboardProvider);
      await ref.read(leaderboardProvider.future);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        6,
        AppSpacing.screenGutter,
        32,
      ),
      child: SeasonRankingPanel(onRefresh: refresh),
    );
  }
}

class _GeneralRankingViewWidget extends ConsumerWidget {
  const _GeneralRankingViewWidget({this.badgeSize});

  final double? badgeSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaderboard = ref.watch(leaderboardProvider);
    Future<void> refresh() async {
      ref.invalidate(leaderboardProvider);
      await ref.read(leaderboardProvider.future);
    }

    return leaderboard.when(
      loading: () => const Center(
        child: GrintaLoader.page(
          message: 'Le classement se met en place…',
          semanticLabel: 'Chargement du classement général',
        ),
      ),
      error: (_, __) => const _MessageCard(
        title: 'Classement indisponible',
        icon: Icons.wifi_off_rounded,
        message: 'Le classement général n\'a pas pu être chargé.',
        tone: GrintaEmptyTone.alert,
      ),
      data: (entries) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          6,
          AppSpacing.screenGutter,
          32,
        ),
        child: _LeaderboardCard(
          entries: entries,
          points: (entry) => entry.totalPoints.roundToDouble(),
          onRefresh: refresh,
          badgeSize: badgeSize,
        ),
      ),
    );
  }
}
