part of 'pronos_hub_page.dart';

final _calendarPredictionProvider = FutureProvider.autoDispose
    .family<MatchPredictionItem?, String>((ref, matchId) {
  return ref.watch(predictionsRepositoryProvider).fetchMatchPrediction(matchId);
});

enum _MatchCalendarTab { upcoming, finished }

class _CalendarSection extends ConsumerStatefulWidget {
  const _CalendarSection();

  @override
  ConsumerState<_CalendarSection> createState() => _CalendarSectionState();
}

class _CalendarSectionState extends ConsumerState<_CalendarSection> {
  _MatchCalendarTab _tab = _MatchCalendarTab.upcoming;

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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<_MatchCalendarTab>(
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(
                  value: _MatchCalendarTab.upcoming,
                  icon: Icon(Icons.calendar_month_outlined),
                  label: Text('À venir'),
                ),
                ButtonSegment(
                  value: _MatchCalendarTab.finished,
                  icon: Icon(Icons.history_rounded),
                  label: Text('Terminés'),
                ),
              ],
              selected: {_tab},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                setState(() => _tab = selection.first);
              },
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
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
                else if (_tab == _MatchCalendarTab.upcoming)
                  ..._buildUpcoming(
                    context,
                    upcomingMatches,
                    predictionsByMatchId,
                    predictionState,
                    isAdmin,
                  )
                else
                  ..._buildFinished(finishedMatches, isAdmin),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildUpcoming(
    BuildContext context,
    List<MatchModel> matches,
    Map<String, MatchPredictionItem> predictionsByMatchId,
    PredictionsState predictionState,
    bool isAdmin,
  ) {
    if (matches.isEmpty) {
      return const [_MessageCard(message: 'Aucun match à venir.')];
    }
    if (predictionState.isLoading) return const [_LoadingCard()];

    return matches.map((match) {
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
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => context.push(
                              '/matches/${match.id}/finalize',
                            ),
                            icon: const Text('👑'),
                            label: const Text('Entrer les stats'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: _DeleteMatchButton(matchId: match.id)),
                      ],
                    ),
                  ],
                ],
              ),
      );
    }).toList();
  }

  List<Widget> _buildFinished(List<MatchModel> matches, bool isAdmin) {
    if (matches.isEmpty) {
      return const [_MessageCard(message: 'Aucun match terminé.')];
    }

    return matches
        .map(
          (match) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CalendarMatchCard(match: match, isAdmin: isAdmin),
          ),
        )
        .toList();
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
                Row(
                  children: [
                    Expanded(
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
                    const SizedBox(width: 10),
                    Expanded(child: _DeleteMatchButton(matchId: match.id)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteMatchButton extends ConsumerWidget {
  const _DeleteMatchButton({required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: () async {
        final confirmed = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Supprimer ce match ?'),
                content: const Text(
                  'Le match, ses pronostics, ses buteurs et ses statistiques '
                  'seront définitivement supprimés.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Annuler'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Supprimer'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!confirmed || !context.mounted) return;

        await ref.read(matchesControllerProvider.notifier).deleteMatch(matchId);
        ref.invalidate(_calendarPredictionProvider);
        await ref.read(predictionsControllerProvider.notifier).load();
      },
      icon: const Icon(Icons.delete_outline),
      label: const Text('👑 Supprimer'),
    );
  }
}
