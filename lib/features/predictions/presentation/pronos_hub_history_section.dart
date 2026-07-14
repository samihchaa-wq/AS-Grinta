part of 'pronos_hub_page.dart';

final _calendarPredictionProvider = FutureProvider.autoDispose
    .family<MatchPredictionItem?, String>((ref, matchId) {
  return ref.watch(predictionsRepositoryProvider).fetchMatchPrediction(matchId);
});

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

    final upcomingMatches = state.matches
        .where((match) => !match.isFinished)
        .toList()
      ..sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));
    final finishedMatches = state.matches
        .where((match) => match.isFinished)
        .toList()
      ..sort((a, b) => b.kickoffAt.compareTo(a.kickoffAt));
    final predictionsByMatchId = {
      for (final item in predictionState.items) item.matchId: item,
    };

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_calendarPredictionProvider);
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
          else ...[
            const _CalendarGroupTitle(title: 'À venir'),
            const SizedBox(height: 10),
            if (upcomingMatches.isEmpty)
              const _MessageCard(message: 'Aucun match à venir.')
            else if (predictionState.isLoading)
              const _LoadingCard()
            else
              ...upcomingMatches.map((match) {
                final item = predictionsByMatchId[match.id];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: item == null
                      ? _CalendarMatchCard(match: match, isAdmin: isAdmin)
                      : Column(
                          children: [
                            _UpcomingPredictionCard(item: item),
                            if (isAdmin) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.tonalIcon(
                                  onPressed: () => context.push(
                                    '/matches/${match.id}/finalize',
                                  ),
                                  icon: const Text('👑'),
                                  label: const Text('Entrer les stats'),
                                ),
                              ),
                            ],
                          ],
                        ),
                );
              }),
            const SizedBox(height: 12),
            const _CalendarGroupTitle(title: 'Terminés'),
            const SizedBox(height: 10),
            if (finishedMatches.isEmpty)
              const _MessageCard(message: 'Aucun match terminé.')
            else
              ...finishedMatches.map(
                (match) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CalendarMatchCard(
                    match: match,
                    isAdmin: isAdmin,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CalendarGroupTitle extends StatelessWidget {
  const _CalendarGroupTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
    );
  }
}

class _CalendarMatchCard extends ConsumerWidget {
  const _CalendarMatchCard({required this.match, required this.isAdmin});

  final MatchModel match;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prediction = match.isFinished
        ? const AsyncValue<MatchPredictionItem?>.data(null)
        : ref.watch(_calendarPredictionProvider(match.id));
    final opponent = match.opponentName ?? 'Adversaire';
    final grintaScore = match.grintaScore ?? 0;
    final opponentScore = match.opponentScore ?? 0;
    final homeName = match.isHome ? 'AS Grinta' : opponent;
    final awayName = match.isHome ? opponent : 'AS Grinta';
    final homeScore = match.isHome ? grintaScore : opponentScore;
    final awayScore = match.isHome ? opponentScore : grintaScore;
    final background =
        match.isFinished ? const Color(0xFF24272E) : const Color(0xFF102A56);
    final outline =
        match.isFinished ? const Color(0xFF5F646E) : const Color(0xFF4B8DFF);
    final statusColor =
        match.isFinished ? const Color(0xFFB7BBC4) : const Color(0xFF7FB0FF);

    return Card(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: outline, width: 1.2),
      ),
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
                          color: statusColor,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                AppFormats.dateTime(match.kickoffAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: match.isFinished
                          ? const Color(0xFFB7BBC4)
                          : const Color(0xFFA9C8FF),
                    ),
              ),
              if (!match.isFinished) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        context.push('/matches/${match.id}/prediction'),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(
                      prediction.maybeWhen(
                        data: (item) => item?.isFilled == true
                            ? 'Modifier mon prono'
                            : 'Rentrer mon prono',
                        orElse: () => 'Rentrer mon prono',
                      ),
                    ),
                  ),
                ),
              ],
              if (isAdmin) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () =>
                        context.push('/matches/${match.id}/finalize'),
                    icon: const Text('👑'),
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
