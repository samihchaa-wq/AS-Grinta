part of 'pronos_hub_page.dart';

class _CalendarSection extends ConsumerStatefulWidget {
  const _CalendarSection();

  @override
  ConsumerState<_CalendarSection> createState() => _CalendarSectionState();
}

class _CalendarSectionState extends ConsumerState<_CalendarSection> {
  _CalendarFilter _filter = _CalendarFilter.finished;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(matchesControllerProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchesControllerProvider);
    final isAdmin =
        ref.watch(authControllerProvider).profile?.role == AuthRole.admin;
    final matches = state.matches.where((match) {
      return _filter == _CalendarFilter.finished
          ? match.isFinished
          : !match.isFinished;
    }).toList()
      ..sort(
        (a, b) => _filter == _CalendarFilter.finished
            ? b.kickoffAt.compareTo(a.kickoffAt)
            : a.kickoffAt.compareTo(b.kickoffAt),
      );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<_CalendarFilter>(
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(
                  value: _CalendarFilter.finished,
                  label: Text('Terminé'),
                ),
                ButtonSegment(
                  value: _CalendarFilter.upcoming,
                  label: Text('À venir'),
                ),
              ],
              selected: {_filter},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                setState(() => _filter = selection.first);
              },
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.read(matchesControllerProvider.notifier).load(
                  seasonId: state.selectedSeasonId,
                ),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                if (state.isLoading)
                  const _LoadingCard()
                else if (state.error != null)
                  _MessageCard(message: state.error!)
                else if (matches.isEmpty)
                  _MessageCard(
                    message: _filter == _CalendarFilter.finished
                        ? 'Aucun match terminé pour le moment.'
                        : 'Aucun match à venir pour le moment.',
                  )
                else
                  ...matches.map(
                    (match) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CalendarMatchCard(
                        match: match,
                        isAdmin: isAdmin,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CalendarMatchCard extends StatelessWidget {
  const _CalendarMatchCard({required this.match, required this.isAdmin});

  final MatchModel match;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final opponent = match.opponentName ?? 'Adversaire';
    final grintaScore = match.grintaScore ?? 0;
    final opponentScore = match.opponentScore ?? 0;
    final homeName = match.isHome ? 'AS Grinta' : opponent;
    final awayName = match.isHome ? opponent : 'AS Grinta';
    final homeScore = match.isHome ? grintaScore : opponentScore;
    final awayScore = match.isHome ? opponentScore : grintaScore;

    return Card(
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
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                AppFormats.dateTime(match.kickoffAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
              if (isAdmin) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () =>
                        context.push('/matches/${match.id}/finalize'),
                    icon: const Icon(Icons.fact_check_outlined),
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
