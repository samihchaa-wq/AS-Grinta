part of 'pronos_hub_page.dart';

class _UpcomingMatchView extends ConsumerStatefulWidget {
  const _UpcomingMatchView();

  @override
  ConsumerState<_UpcomingMatchView> createState() => _UpcomingMatchViewState();
}

class _UpcomingMatchViewState extends ConsumerState<_UpcomingMatchView> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(predictionsControllerProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            data: (_) => const _UpcomingPredictionCard(),
          ),
        ],
      ),
    );
  }
}
