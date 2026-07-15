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
  final _upcomingSliverKey = GlobalKey();
  final _previousMatchKey = GlobalKey();
  final _scrollController = ScrollController(keepScrollOffset: false);
  bool _didPositionInitialList = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await Future.wait([
        ref.read(matchesControllerProvider.notifier).load(allSeasons: true),
        ref.read(predictionsControllerProvider.notifier).load(),
      ]);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchesControllerProvider);
    final predictionState = ref.watch(predictionsControllerProvider);
    final isAdmin =
        ref.watch(authControllerProvider).profile?.role == AuthRole.admin;

    final matches = state.matches.toList();
    final finishedMatches = matches.where((match) => match.isFinished).toList()
      ..sort((a, b) => b.kickoffAt.compareTo(a.kickoffAt));
    final upcomingMatches = matches.where((match) => !match.isFinished).toList()
      ..sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));
    final nextMatchId = upcomingMatches.firstOrNull?.id;

    final predictionsByMatchId = {
      for (final item in predictionState.items) item.matchId: item,
    };
    final nextEditableMatchId = upcomingMatches
        .map((match) => predictionsByMatchId[match.id])
        .whereType<MatchPredictionItem>()
        .where((item) => !item.isClosed)
        .map((item) => item.matchId)
        .firstOrNull;

    final hasUpcomingMatches =
        !state.isLoading && state.error == null && upcomingMatches.isNotEmpty;

    if (!_didPositionInitialList && hasUpcomingMatches) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _didPositionInitialList) return;

        if (finishedMatches.isNotEmpty) {
          final previousMatchContext = _previousMatchKey.currentContext;
          if (previousMatchContext == null) return;
          Scrollable.ensureVisible(
            previousMatchContext,
            alignment: 0,
            duration: Duration.zero,
          );
        }

        _didPositionInitialList = true;
      });
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(_calendarPredictionProvider)
          ..invalidate(inlineMatchPredictionProvider);
        await Future.wait([
          ref.read(matchesControllerProvider.notifier).load(
                seasonId: state.selectedSeasonId,
                allSeasons: true,
              ),
          ref.read(predictionsControllerProvider.notifier).load(),
        ]);
      },
      child: CustomScrollView(
        controller: _scrollController,
        center: hasUpcomingMatches ? _upcomingSliverKey : null,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (state.isLoading)
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 32),
              sliver: SliverToBoxAdapter(child: _LoadingCard()),
            )
          else if (state.error != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              sliver: SliverToBoxAdapter(
                child: _MessageCard(message: state.error!),
              ),
            )
          else if (matches.isEmpty)
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 32),
              sliver: SliverToBoxAdapter(
                child: _MessageCard(message: 'Aucun match.'),
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final match = finishedMatches[index];
                    final isPreviousMatch = index == 0;
                    return Padding(
                      key: isPreviousMatch ? _previousMatchKey : null,
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CalendarMatchCard(
                        match: match,
                        isAdmin: isAdmin,
                        isNextMatch: false,
                      ),
                    );
                  },
                  childCount: finishedMatches.length,
                ),
              ),
            ),
            SliverPadding(
              key: _upcomingSliverKey,
              padding: EdgeInsets.fromLTRB(
                16,
                finishedMatches.isEmpty ? 16 : 2,
                16,
                32,
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final match = upcomingMatches[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _CalendarMatchCard(
                        match: match,
                        isAdmin: isAdmin,
                        isNextMatch: match.id == nextMatchId,
                        predictionAvailable:
                            match.id == nextEditableMatchId,
                      ),
                    );
                  },
                  childCount: upcomingMatches.length,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CalendarMatchCard extends ConsumerWidget {
  const _CalendarMatchCard({
    required this.match,
    required this.isAdmin,
    required this.isNextMatch,
    this.predictionAvailable = false,
  });

  final MatchModel match;
  final bool isAdmin;
  final bool isNextMatch;
  final bool predictionAvailable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opponent = match.opponentName ?? 'Adversaire';
    final grintaScore = match.grintaScore ?? 0;
    final opponentScore = match.opponentScore ?? 0;
    final homeName = match.isHome ? 'AS Grinta' : opponent;
    final awayName = match.isHome ? opponent : 'AS Grinta';
    final homeScore = match.isHome ? grintaScore : opponentScore;
    final awayScore = match.isHome ? opponentScore : grintaScore;

    final Color background;
    final Color outline;
    final Color statusColor;
    final Color dateColor;
    final String statusLabel;

    if (match.isFinished) {
      background = const Color(0xFF24272E);
      outline = const Color(0xFF5F646E);
      statusColor = const Color(0xFFB7BBC4);
      dateColor = const Color(0xFFB7BBC4);
      statusLabel = 'Terminé';
    } else if (isNextMatch) {
      background = const Color(0xFF25164F);
      outline = const Color(0xFF9B6CFF);
      statusColor = const Color(0xFFCAB5FF);
      dateColor = const Color(0xFFD7C8FF);
      statusLabel = 'Prochain';
    } else {
      background = const Color(0xFF102A56);
      outline = const Color(0xFF4B8DFF);
      statusColor = const Color(0xFF7FB0FF);
      dateColor = const Color(0xFFA9C8FF);
      statusLabel = 'À venir';
    }

    return Card(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: outline, width: isNextMatch ? 1.8 : 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(
          predictionAvailable
              ? '/matches/${match.id}/prediction'
              : '/matches/${match.id}',
        ),
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
                          : '$homeName vs $awayName',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    statusLabel,
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
                      color: dateColor,
                    ),
              ),
              if (!match.isFinished) ...[
                const SizedBox(height: 12),
                Text(
                  predictionAvailable
                      ? 'Ton pari est disponible.'
                      : 'Le pronostic s’ouvrira lorsque les matchs précédents seront fermés.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                ),
              ],
              if (isAdmin) ...[
                const SizedBox(height: 14),
                _AdminMatchActions(match: match),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminMatchActions extends StatelessWidget {
  const _AdminMatchActions({required this.match});

  final MatchModel match;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: () => context.push('/matches/${match.id}/finalize'),
            icon: const Text('👑'),
            label: Text(
              match.isFinished ? 'Changer les stats' : 'Entrer les stats',
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: _DeleteMatchButton(matchId: match.id)),
      ],
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
                  'seront définitivement supprimés. Les classements seront recalculés.',
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
        ref
          ..invalidate(_calendarPredictionProvider)
          ..invalidate(inlineMatchPredictionProvider)
          ..invalidate(leaderboardProvider)
          ..invalidate(enhancedSeasonGaugesProvider)
          ..invalidate(enhancedSeasonCompletedMatchesProvider)
          ..invalidate(matchDetailsProvider(matchId));
        await ref.read(predictionsControllerProvider.notifier).load();
      },
      icon: const Icon(Icons.delete_outline),
      label: const Text('👑 Supprimer'),
    );
  }
}
