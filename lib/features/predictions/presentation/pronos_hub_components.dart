part of 'pronos_hub_page.dart';

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({
    required this.entries,
    required this.points,
    this.showMatchStats = false,
  });

  final List<LeaderboardEntry> entries;
  final double Function(LeaderboardEntry) points;
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

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (showMatchStats)
            const _MatchLeaderboardHeader()
          else
            const _GeneralLeaderboardHeader(),
          const Divider(height: 1),
          for (var index = 0; index < sorted.length; index++) ...[
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
            if (index != sorted.length - 1) const Divider(height: 1),
          ],
        ],
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text('Joueurs', style: style)),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text('Joueurs', style: style)),
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
  });

  final int rank;
  final String name;
  final String firstValue;
  final String secondValue;
  final String points;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '$rank',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
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

class _ScoreColumn extends StatelessWidget {
  const _ScoreColumn({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final int value;
  final bool enabled;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: enabled && value > 0 ? onMinus : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('$value', style: Theme.of(context).textTheme.headlineMedium),
            IconButton(
              onPressed: enabled ? onPlus : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ],
    );
  }
}

class _OddTile extends ConsumerWidget {
  const _OddTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(predictionsControllerProvider).items;
    final item = items.isEmpty ? null : items.first;
    final selected = item != null &&
        switch (label) {
          '1' => item.scoreGrinta > item.scoreOpponent,
          'N' => item.scoreGrinta == item.scoreOpponent,
          '2' => item.scoreGrinta < item.scoreOpponent,
          _ => false,
        };
    final scheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? scheme.primary.withValues(alpha: .10) : null,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: selected ? scheme.primary : null,
                  fontWeight: selected ? FontWeight.w800 : null,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: selected ? scheme.primary : null,
                  fontWeight: selected ? FontWeight.w900 : null,
                ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.outline),
      ),
      child: child,
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
