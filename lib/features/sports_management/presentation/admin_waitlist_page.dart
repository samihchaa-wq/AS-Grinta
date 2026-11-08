import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/core/widgets/sticky_header_table.dart';
import 'package:as_grinta/features/sports_management/data/sport_waitlist_repository.dart';
import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AdminWaitlistPage extends ConsumerStatefulWidget {
  const AdminWaitlistPage({super.key, this.editable = true});

  /// Faux pour l'écran accessible à tout joueur depuis Paramètres : la
  /// liste s'affiche alors en lecture seule, sans réordonner ni modifier
  /// le nombre de fois en liste d'attente.
  final bool editable;

  @override
  ConsumerState<AdminWaitlistPage> createState() => _AdminWaitlistPageState();
}

class _AdminWaitlistPageState extends ConsumerState<AdminWaitlistPage> {
  SportWaitlist? _waitlist;
  List<SportWaitlistEntry> _entries = const [];
  final Set<String> _adjustingCounts = <String>{};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(sportWaitlistRepositoryProvider);
      final value = widget.editable
          ? await repository.fetchWaitlist()
          : await repository.fetchWaitlistReadOnly();
      if (!mounted) return;
      setState(() {
        _waitlist = value;
        _entries = List.of(value.entries);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = humanizeError(error);
        _loading = false;
      });
    }
  }

  Future<void> _adjustWaitlistCount(SportWaitlistEntry entry, int delta) async {
    final playerId = entry.seasonPlayerId;
    if (_adjustingCounts.contains(playerId)) return;

    final previousCount = entry.currentSeasonWaitlistCount;
    final newCount = previousCount + delta;
    if (newCount < 0) return;

    setState(() {
      _adjustingCounts.add(playerId);
      _entries = [
        for (final current in _entries)
          if (current.seasonPlayerId == playerId)
            current.copyWith(currentSeasonWaitlistCount: newCount)
          else
            current,
      ];
    });

    try {
      await ref
          .read(sportWaitlistRepositoryProvider)
          .setWaitlistManualCount(seasonPlayerId: playerId, count: newCount);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _entries = [
          for (final current in _entries)
            if (current.seasonPlayerId == playerId)
              current.copyWith(currentSeasonWaitlistCount: previousCount)
            else
              current,
        ];
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(humanizeError(error))));
    } finally {
      if (mounted) {
        setState(() => _adjustingCounts.remove(playerId));
      }
    }
  }

  StickyTableRow _tableRow(int index) {
    final entry = _entries[index];
    return StickyTableRow(
      pinned: _WaitlistPinnedRow(
        key: ValueKey('waitlist-row-${entry.seasonPlayerId}'),
        index: index,
        entry: entry,
      ),
      scrollable: _WaitlistScrollableRow(
        entry: entry,
        editable: widget.editable,
        adjustingCount: _adjustingCounts.contains(entry.seasonPlayerId),
        onIncrement: () => _adjustWaitlistCount(entry, 1),
        onDecrement: () => _adjustWaitlistCount(entry, -1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GrintaAppBar(
        title: const Text('Liste d’attente'),
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: GrintaProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(_error!),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Réessayer')),
        ],
      );
    }

    final waitlist = _waitlist;
    if (waitlist == null || _entries.isEmpty) {
      return const Center(
        child: GrintaEmptyState(
          icon: Icons.format_list_numbered_rounded,
          title: 'Aucun joueur dans la saison',
          message: 'Ajoute des joueurs à l’effectif pour construire l’ordre '
              'de la liste d’attente.',
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final pinnedWidth =
                    (constraints.maxWidth * .34).clamp(112.0, 150.0).toDouble();
                return StickyHeaderTableCard(
                  key: const ValueKey('waitlist-table'),
                  onRefresh: _load,
                  minWidth: constraints.maxWidth,
                  pinnedWidth: pinnedWidth,
                  pinnedHeader: const _WaitlistPinnedHeader(),
                  scrollableHeader: const _WaitlistScrollableHeader(),
                  rows: [
                    for (var index = 0; index < _entries.length; index++)
                      _tableRow(index),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitlistPinnedHeader extends StatelessWidget {
  const _WaitlistPinnedHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Text(
        'Joueurs',
        textAlign: TextAlign.center,
        style: grintaTableHeaderTextStyle(context),
      ),
    );
  }
}

class _WaitlistScrollableHeader extends StatelessWidget {
  const _WaitlistScrollableHeader();

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).colorScheme.outlineVariant;
    final style = grintaTableHeaderTextStyle(context).copyWith(height: 1.2);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WaitlistHeaderCell(
          flex: 16,
          label: 'Saison\nprécédente',
          style: style,
          borderColor: borderColor,
        ),
        _WaitlistHeaderCell(
          flex: 18,
          label: 'Tour cette\nsaison',
          style: style,
          borderColor: borderColor,
          drawRightBorder: false,
        ),
      ],
    );
  }
}

class _WaitlistHeaderCell extends StatelessWidget {
  const _WaitlistHeaderCell({
    required this.flex,
    required this.label,
    required this.style,
    required this.borderColor,
    this.drawRightBorder = true,
  });

  final int flex;
  final String label;
  final TextStyle style;
  final Color borderColor;
  final bool drawRightBorder;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 12),
        decoration: BoxDecoration(
          border: drawRightBorder
              ? Border(right: BorderSide(color: borderColor))
              : null,
        ),
        child: Text(label, textAlign: TextAlign.center, style: style),
      ),
    );
  }
}

class _WaitlistPinnedRow extends StatelessWidget {
  const _WaitlistPinnedRow({
    super.key,
    required this.index,
    required this.entry,
  });

  final int index;
  final SportWaitlistEntry entry;

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).colorScheme.outlineVariant;
    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: borderColor)),
      ),
      child: Padding(
        padding: grintaTablePinnedRowPadding,
        child: Row(
          children: [
            GrintaTableRankCell(rank: index + 1),
            Expanded(
              child: Text(
                entry.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: grintaTableCellTextStyle(
                  context,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaitlistScrollableRow extends StatelessWidget {
  const _WaitlistScrollableRow({
    required this.entry,
    required this.editable,
    required this.adjustingCount,
    required this.onIncrement,
    required this.onDecrement,
  });

  final SportWaitlistEntry entry;
  final bool editable;
  final bool adjustingCount;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).colorScheme.outlineVariant;
    final total = entry.previousSeasonMatchCount;
    final attendance = entry.previousSeasonAttendanceCount;
    final previousSeasonPresence = total > 0 ? '$attendance' : 'Aucune donnée';
    final waitlistCount = entry.currentSeasonWaitlistCount;
    final valueStyle = grintaTableCellTextStyle(context);

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 16,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 17),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: borderColor)),
            ),
            child: Text(
              previousSeasonPresence,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: valueStyle,
            ),
          ),
        ),
        Expanded(
          flex: 18,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: editable
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CompactIconButton(
                        key: ValueKey(
                          'waitlist-decrement-${entry.seasonPlayerId}',
                        ),
                        icon: Icons.remove_circle_outline,
                        onPressed: !adjustingCount && waitlistCount > 0
                            ? onDecrement
                            : null,
                      ),
                      SizedBox(
                        width: 26,
                        child: Text(
                          '$waitlistCount',
                          key: ValueKey(
                            'waitlist-count-${entry.seasonPlayerId}',
                          ),
                          textAlign: TextAlign.center,
                          style: valueStyle,
                        ),
                      ),
                      _CompactIconButton(
                        key: ValueKey(
                          'waitlist-increment-${entry.seasonPlayerId}',
                        ),
                        icon: Icons.add_circle_outline,
                        onPressed: adjustingCount ? null : onIncrement,
                      ),
                    ],
                  )
                : Text(
                    '$waitlistCount',
                    key: ValueKey('waitlist-count-${entry.seasonPlayerId}'),
                    textAlign: TextAlign.center,
                    style: valueStyle,
                  ),
          ),
        ),
      ],
    );

    return content;
  }
}

class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 44),
    );
  }
}
