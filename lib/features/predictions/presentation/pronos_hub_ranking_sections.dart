part of 'pronos_hub_page.dart';

/// Classement des pronostics de match : la seule compétition de pronostic.
class _GeneralRankingsSection extends ConsumerWidget {
  const _GeneralRankingsSection({this.badgeSize});

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
        message: 'Le classement des matchs n’a pas pu être chargé.',
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
          onRefresh: refresh,
          badgeSize: badgeSize,
        ),
      ),
    );
  }
}
