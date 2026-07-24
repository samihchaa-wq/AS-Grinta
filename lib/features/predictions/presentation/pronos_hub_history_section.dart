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
  final _scrollController = ScrollController();

  /// Repère la carte du prochain match pour l'amener en haut à l'ouverture.
  final _nextMatchKey = GlobalKey();

  /// L'auto-centrage sur le prochain match ne se fait qu'une fois par ouverture.
  bool _autoScrolledToNext = false;

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

  void _scrollToNextMatch(int attempt) {
    if (!mounted) return;
    final targetContext = _nextMatchKey.currentContext;
    if (targetContext == null) {
      if (attempt < 10) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToNextMatch(attempt + 1),
        );
      }
      return;
    }
    Scrollable.ensureVisible(
      targetContext,
      alignment: 0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchesControllerProvider);
    final isAdmin = ref.watch(isAdminViewProvider);

    final matches = state.matches.toList();
    final orderedMatches = matches.toList()
      ..sort((a, b) => b.kickoffAt.compareTo(a.kickoffAt));
    final upcomingMatches = matches.where((match) => !match.isFinished).toList()
      ..sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));
    final nextMatchId = upcomingMatches.firstOrNull?.id;

    if (!_autoScrolledToNext &&
        !state.isLoading &&
        matches.isNotEmpty &&
        nextMatchId != null) {
      _autoScrolledToNext = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToNextMatch(0),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(_calendarPredictionProvider)
          ..invalidate(inlineMatchPredictionProvider);
        await Future.wait([
          ref
              .read(matchesControllerProvider.notifier)
              .load(seasonId: state.selectedSeasonId, allSeasons: true),
          ref.read(predictionsControllerProvider.notifier).load(),
        ]);
      },
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (isAdmin)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '👑 Ajouter un match',
                        iconSize: 48,
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const MatchFormPage(),
                            ),
                          );
                          if (!context.mounted) return;
                          await ref
                              .read(matchesControllerProvider.notifier)
                              .load(allSeasons: true);
                        },
                        icon: const Icon(Icons.add_circle),
                      ),
                      Text(
                        '👑 Ajouter un match',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (state.isLoading)
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 32),
              sliver: SliverToBoxAdapter(child: _LoadingCard()),
            )
          else if (state.error != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              sliver: SliverToBoxAdapter(
                child: _MessageCard(
                  title: 'Historique indisponible',
                  icon: Icons.wifi_off_rounded,
                  message: state.error!,
                  tone: GrintaEmptyTone.alert,
                ),
              ),
            )
          else if (matches.isEmpty)
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 32),
              sliver: SliverToBoxAdapter(
                child: _MessageCard(
                  title: 'Aucun match joué',
                  icon: Icons.history_rounded,
                  message: 'Les matchs terminés et leurs pronos s\'afficheront '
                      'ici.',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final match = orderedMatches[index];
                  final isNext = match.id == nextMatchId;
                  return Padding(
                    key: isNext ? _nextMatchKey : null,
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _CalendarMatchCard(
                      match: match,
                      isAdmin: isAdmin,
                      isNextMatch: isNext,
                    ),
                  );
                }, childCount: orderedMatches.length),
              ),
            ),
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
  });

  final MatchModel match;
  final bool isAdmin;
  final bool isNextMatch;

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

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: MatchFixture(
                  homeName: homeName,
                  awayName: awayName,
                  grintaIsHome: match.isHome,
                  homeScore: homeScore,
                  awayScore: awayScore,
                  finished: match.isFinished,
                ),
              ),
              // Le score suffit à indiquer qu'un match est terminé : on ne
              // montre l'étiquette de statut que pour les matchs à venir.
              if (!match.isFinished) ...[
                const SizedBox(width: 12),
                Text(
                  statusLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            AppFormats.dateTime(match.kickoffAt),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: dateColor),
          ),
          if (isAdmin) ...[
            const SizedBox(height: 14),
            _AdminMatchActions(match: match),
          ],
        ],
      ),
    );

    return Card(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: outline, width: isNextMatch ? 1.8 : 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: match.isFinished || isNextMatch
          ? InkWell(
              onTap: () => context.push(
                match.isFinished
                    ? '/matches/${match.id}'
                    : '/matches/${match.id}/lineup?section=effectif',
              ),
              child: content,
            )
          : content,
    );
  }
}

/// Actions admin d'un match regroupées dans un unique bouton « ✏️ » :
/// Modifier, Stats et Supprimer.
class _AdminMatchActions extends ConsumerWidget {
  const _AdminMatchActions({required this.match});

  final MatchModel match;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MatchFormPage(match: match)),
    );
    if (!context.mounted) return;
    ref
      ..invalidate(_calendarPredictionProvider)
      ..invalidate(inlineMatchPredictionProvider)
      ..invalidate(matchDetailsProvider(match.id));
    await ref.read(predictionsControllerProvider.notifier).load();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
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

    await ref.read(matchesControllerProvider.notifier).deleteMatch(match.id);
    ref
      ..invalidate(_calendarPredictionProvider)
      ..invalidate(inlineMatchPredictionProvider)
      ..invalidate(leaderboardProvider)
      ..invalidate(enhancedSeasonGaugesProvider)
      ..invalidate(enhancedSeasonCompletedMatchesProvider)
      ..invalidate(matchDetailsProvider(match.id));
    await ref.read(predictionsControllerProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const AdminBadge(),
        PopupMenuButton<String>(
          tooltip: 'Options du match',
          icon: const Text('✏️', style: TextStyle(fontSize: 22)),
          onSelected: (value) {
            switch (value) {
              case 'edit':
                _edit(context, ref);
              case 'stats':
                context.push('/matches/${match.id}/finalize');
              case 'delete':
                _delete(context, ref);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem<String>(
              value: 'edit',
              child: _ActionRow(emoji: '⚙️', label: 'Modifier'),
            ),
            PopupMenuItem<String>(
              value: 'stats',
              child: _ActionRow(emoji: '📈', label: 'Stats'),
            ),
            PopupMenuItem<String>(
              value: 'delete',
              child: _ActionRow(emoji: '🚫', label: 'Supprimer'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.emoji, required this.label});

  final String emoji;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}
