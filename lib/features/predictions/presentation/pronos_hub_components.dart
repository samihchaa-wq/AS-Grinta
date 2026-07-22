part of 'pronos_hub_page.dart';

enum _LbCol { name, first, second, points }

class _LeaderboardCard extends StatefulWidget {
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
  State<_LeaderboardCard> createState() => _LeaderboardCardState();
}

class _LeaderboardCardState extends State<_LeaderboardCard> {
  _LbCol _sort = _LbCol.points;
  bool _desc = true;

  double _first(LeaderboardEntry e) =>
      widget.showMatchStats ? e.matchBons.toDouble() : e.matchPoints * 100;
  double _second(LeaderboardEntry e) =>
      widget.showMatchStats ? e.matchExacts.toDouble() : e.seasonPoints;

  void _onSort(_LbCol col) {
    setState(() {
      if (_sort == col) {
        _desc = !_desc;
      } else {
        _sort = col;
        _desc = col != _LbCol.name;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return const _MessageCard(
        title: 'Aucun point pour le moment',
        message: 'Le classement se remplit dès les premiers matchs notés.',
      );
    }

    final sorted = [...widget.entries]..sort((a, b) {
        int cmp;
        switch (_sort) {
          case _LbCol.name:
            cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          case _LbCol.first:
            cmp = _first(a).compareTo(_first(b));
          case _LbCol.second:
            cmp = _second(a).compareTo(_second(b));
          case _LbCol.points:
            cmp = widget.points(a).compareTo(widget.points(b));
        }
        // Départage : plus de points d'abord, puis nom.
        if (cmp == 0) cmp = widget.points(a).compareTo(widget.points(b));
        if (cmp == 0) {
          cmp = b.name.toLowerCase().compareTo(a.name.toLowerCase());
        }
        return _desc ? -cmp : cmp;
      });

    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w800,
        );

    return StickyHeaderTableCard(
      onRefresh: widget.onRefresh,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
        child: Row(
          children: [
            SortableHeaderCell(
              label: 'Joueurs',
              flex: 6,
              align: TextAlign.start,
              active: _sort == _LbCol.name,
              descending: _desc,
              onTap: () => _onSort(_LbCol.name),
              style: style,
            ),
            SortableHeaderCell(
              label: widget.showMatchStats ? 'Bons' : 'Matchs',
              flex: 2,
              active: _sort == _LbCol.first,
              descending: _desc,
              onTap: () => _onSort(_LbCol.first),
              style: style,
            ),
            SortableHeaderCell(
              label: widget.showMatchStats ? 'Exacts' : 'Buteurs',
              flex: 2,
              active: _sort == _LbCol.second,
              descending: _desc,
              onTap: () => _onSort(_LbCol.second),
              style: style,
            ),
            SortableHeaderCell(
              label: 'Points',
              flex: 2,
              align: TextAlign.end,
              active: _sort == _LbCol.points,
              descending: _desc,
              onTap: () => _onSort(_LbCol.points),
              style: style,
            ),
          ],
        ),
      ),
      rows: [
        for (var index = 0; index < sorted.length; index++)
          _LeaderboardRowLayout(
            rank: index + 1,
            profileId: sorted[index].profileId,
            name: sorted[index].name,
            firstValue: '${_first(sorted[index]).round()}',
            secondValue: '${_second(sorted[index]).round()}',
            points: '${widget.points(sorted[index]).round()}',
          ),
      ],
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
  const _MessageCard({
    required this.title,
    this.icon = Icons.scoreboard_rounded,
    this.message,
    this.tone = GrintaEmptyTone.neutral,
  });

  final String title;
  final IconData icon;
  final String? message;
  final GrintaEmptyTone tone;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: GrintaEmptyState(
        icon: icon,
        title: title,
        message: message,
        tone: tone,
      ),
    );
  }
}
