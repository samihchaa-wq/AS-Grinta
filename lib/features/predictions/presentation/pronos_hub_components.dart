part of 'pronos_hub_page.dart';

enum _LbCol { name, first, second, points }

const _leaderboardValueFlex = 10;
const _leaderboardPointsFlex = 12;

class _LeaderboardCard extends ConsumerStatefulWidget {
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
  ConsumerState<_LeaderboardCard> createState() => _LeaderboardCardState();
}

class _LeaderboardCardState extends ConsumerState<_LeaderboardCard> {
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

    final currentProfileId = ref.watch(
      authControllerProvider.select((state) => state.profile?.id),
    );
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

    final style = grintaTableHeaderTextStyle(
      context,
      color: AppTheme.textSecondary,
    );

    return StickyHeaderTableCard(
      minWidth: 0,
      onRefresh: widget.onRefresh,
      pinnedHeader: Padding(
        padding: grintaTablePinnedHeaderPadding,
        child: SortableHeaderCell(
          label: 'Joueurs',
          align: TextAlign.start,
          active: _sort == _LbCol.name,
          descending: _desc,
          onTap: () => _onSort(_LbCol.name),
          style: style,
        ),
      ),
      scrollableHeader: Padding(
        padding: grintaTableScrollableHeaderPadding,
        child: Row(
          children: [
            SortableHeaderCell(
              label: widget.showMatchStats ? 'Bons' : 'Matchs',
              flex: _leaderboardValueFlex,
              active: _sort == _LbCol.first,
              descending: _desc,
              onTap: () => _onSort(_LbCol.first),
              style: style,
            ),
            SortableHeaderCell(
              label: widget.showMatchStats ? 'Exacts' : 'Buteurs',
              flex: _leaderboardValueFlex,
              active: _sort == _LbCol.second,
              descending: _desc,
              onTap: () => _onSort(_LbCol.second),
              style: style,
            ),
            SortableHeaderCell(
              label: 'Points',
              flex: _leaderboardPointsFlex,
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
          _leaderboardRow(
            context,
            rank: index + 1,
            profileId: sorted[index].profileId,
            name: sorted[index].name,
            firstValue: '${_first(sorted[index]).round()}',
            secondValue: '${_second(sorted[index]).round()}',
            points: '${widget.points(sorted[index]).round()}',
            isCurrentUser: currentProfileId != null &&
                sorted[index].profileId == currentProfileId,
          ),
      ],
    );
  }
}

StickyTableRow _leaderboardRow(
  BuildContext context, {
  required int rank,
  required String name,
  required String? profileId,
  required String firstValue,
  required String secondValue,
  required String points,
  required bool isCurrentUser,
}) {
  final valueStyle = grintaTableCellTextStyle(context);

  Widget pinned = Padding(
    padding: grintaTablePinnedRowPadding,
    child: Row(
      children: [
        SizedBox(
          width: 22,
          child: Text(
            '$rank',
            style: grintaTableRankTextStyle(
              context,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: NameWithBadges(profileId: profileId, name: name),
        ),
      ],
    ),
  );

  Widget scrollable = Padding(
    padding: grintaTableScrollableRowPadding,
    child: Row(
      children: [
        Expanded(
          flex: _leaderboardValueFlex,
          child: Text(
            firstValue,
            textAlign: TextAlign.center,
            style: valueStyle,
          ),
        ),
        Expanded(
          flex: _leaderboardValueFlex,
          child: Text(
            secondValue,
            textAlign: TextAlign.center,
            style: valueStyle,
          ),
        ),
        Expanded(
          flex: _leaderboardPointsFlex,
          child: Text(points, textAlign: TextAlign.end, style: valueStyle),
        ),
      ],
    ),
  );

  if (isCurrentUser) {
    final accent = Theme.of(context).colorScheme.secondary;
    pinned = DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .14),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      child: pinned,
    );
    scrollable = DecoratedBox(
      decoration: BoxDecoration(color: accent.withValues(alpha: .14)),
      child: scrollable,
    );
  }

  return StickyTableRow(pinned: pinned, scrollable: scrollable);
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: GrintaProgressIndicator()),
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
