part of 'pronos_hub_page.dart';

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({
    required this.entries,
    required this.points,
    this.onRefresh,
    this.showMatchStats = false,
  });

  final List<LeaderboardEntry> entries;
  final double Function(LeaderboardEntry) points;
  final Future<void> Function()? onRefresh;
  final bool showMatchStats;

  @override
  Widget build(BuildContext context) {
    final sorted = [...entries]..sort((a, b) {
        final byPoints = points(b).compareTo(points(a));
        return byPoints != 0 ? byPoints : a.name.compareTo(b.name);
      });

    if (sorted.isEmpty) {
      return const _MessageCard(message: 'Aucun point pour le moment.');
    }

    return StickyHeaderTableCard(
      onRefresh: onRefresh,
      header: showMatchStats
          ? const _MatchLeaderboardHeader()
          : const _GeneralLeaderboardHeader(),
      rows: [
        for (var index = 0; index < sorted.length; index++)
          if (showMatchStats)
            _MatchLeaderboardRow(
              rank: index + 1,
              entry: sorted[index],
              points: points(sorted[index]).round(),
            )
          else
            _GeneralLeaderboardRow(
              rank: index + 1,
              entry: sorted[index],
              points: points(sorted[index]).round(),
            ),
      ],
    );
  }
}

class _MatchLeaderboardHeader extends StatelessWidget {
  const _MatchLeaderboardHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w800,
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
      child: Row(
        children: [
          Expanded(flex: 6, child: Text('Joueurs', style: style)),
          Expanded(
            flex: 2,
            child: Text('Bons', style: style, textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 2,
            child: Text('Exacts', style: style, textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 2,
            child: Text('Points', style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _GeneralLeaderboardHeader extends StatelessWidget {
  const _GeneralLeaderboardHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w800,
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
      child: Row(
        children: [
          Expanded(flex: 6, child: Text('Joueurs', style: style)),
          Expanded(
            flex: 2,
            child: Text('Matchs', style: style, textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 2,
            child: Text('Saison', style: style, textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 2,
            child: Text('Points', style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _MatchLeaderboardRow extends StatelessWidget {
  const _MatchLeaderboardRow({
    required this.rank,
    required this.entry,
    required this.points,
  });

  final int rank;
  final LeaderboardEntry entry;
  final int points;

  @override
  Widget build(BuildContext context) {
    return _LeaderboardRowLayout(
      rank: rank,
      profileId: entry.profileId,
      name: entry.name,
      firstValue: '${entry.matchBons}',
      secondValue: '${entry.matchExacts}',
      points: '$points',
    );
  }
}

class _GeneralLeaderboardRow extends StatelessWidget {
  const _GeneralLeaderboardRow({
    required this.rank,
    required this.entry,
    required this.points,
  });

  final int rank;
  final LeaderboardEntry entry;
  final int points;

  @override
  Widget build(BuildContext context) {
    return _LeaderboardRowLayout(
      rank: rank,
      profileId: entry.profileId,
      name: entry.name,
      firstValue: '${(entry.matchPoints * 100).round()}',
      secondValue: '${entry.seasonPoints.round()}',
      points: '$points',
    );
  }
}

class _LeaderboardRowLayout extends StatelessWidget {
  const _LeaderboardRowLayout({
    required this.rank,
    required this.name,
    required this.firstValue,
    required this.secondValue,
    required this.points,
    this.profileId,
  });

  final int rank;
  final String name;
  final String? profileId;
  final String firstValue;
  final String secondValue;
  final String points;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 15, 12, 15),
      child: Row(
        children: [
          Expanded(
            flex: 6,
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: Text(
                    '$rank',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: NameWithBadges(
                    profileId: profileId,
                    name: name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              firstValue,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              secondValue,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              points,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(message),
      ),
    );
  }
}
