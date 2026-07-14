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
    return RefreshIndicator(
      onRefresh: () => ref.read(predictionsControllerProvider.notifier).load(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
        children: const [_UpcomingPredictionCard()],
      ),
    );
  }
}
