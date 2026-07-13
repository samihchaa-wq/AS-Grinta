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

  String _goodPredictionsLabel(int count) =>
      '$count bon${count > 1 ? 's' : ''} pronostic${count > 1 ? 's' : ''}';

  String _exactScoresLabel(int count) =>
      '$count score${count > 1 ? 's' : ''} exact${count > 1 ? 's' : ''}';

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
          for (var index = 0; index < sorted.length; index++) ...[
            ListTile(
              leading: CircleAvatar(
                child: Text(
                  index < 3 ? ['🥇', '🥈', '🥉'][index] : '${index + 1}',
                ),
              ),
              title: Text(
                sorted[index].name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: showMatchStats
                  ? Text(
                      '${_goodPredictionsLabel(sorted[index].matchBons)} · '
                      '${_exactScoresLabel(sorted[index].matchExacts)}',
                    )
                  : Text(
                      'Matchs ${(sorted[index].matchPoints * 100).round()} · '
                      'Saison ${sorted[index].seasonPoints.round()}',
                    ),
              trailing: Text(
                '${points(sorted[index]).round()} pts',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            if (index != sorted.length - 1) const Divider(height: 1),
          ],
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

class _OddTile extends StatelessWidget {
  const _OddTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
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
