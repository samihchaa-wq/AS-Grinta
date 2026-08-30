import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/drag_auto_scroll.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/features/sports_management/data/sport_waitlist_repository.dart';
import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';

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
  bool _saving = false;
  String? _error;
  bool _dirty = false;

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
        _dirty = false;
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

  void _reorderByDrag(SportWaitlistEntry dragged, SportWaitlistEntry target) {
    if (dragged.seasonPlayerId == target.seasonPlayerId) return;
    setState(() {
      final entries = List<SportWaitlistEntry>.of(_entries);
      final fromIndex =
          entries.indexWhere((e) => e.seasonPlayerId == dragged.seasonPlayerId);
      final toIndex =
          entries.indexWhere((e) => e.seasonPlayerId == target.seasonPlayerId);
      if (fromIndex == -1 || toIndex == -1) return;
      final item = entries.removeAt(fromIndex);
      entries.insert(toIndex, item);
      _entries = entries;
      _dirty = true;
    });
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
      await ref.read(sportWaitlistRepositoryProvider).setWaitlistManualCount(
            seasonPlayerId: playerId,
            count: newCount,
          );
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
    } finally {
      if (mounted) {
        setState(() => _adjustingCounts.remove(playerId));
      }
    }
  }

  /// Remet la liste dans l'ordre équitable : d'abord les joueurs les moins
  /// souvent mis en liste d'attente cette saison, puis, à égalité, les
  /// joueurs les moins présents la saison précédente. Le nouvel ordre est
  /// enregistré immédiatement afin que Recalculer soit une action complète.
  Future<void> _recalculateOrder() async {
    if (_saving) return;
    setState(() {
      final entries = List<SportWaitlistEntry>.of(_entries)
        ..sort((a, b) {
          final byWaitlistCount = a.currentSeasonWaitlistCount
              .compareTo(b.currentSeasonWaitlistCount);
          if (byWaitlistCount != 0) return byWaitlistCount;
          return a.previousSeasonAttendanceCount
              .compareTo(b.previousSeasonAttendanceCount);
        });
      _entries = entries;
      _dirty = true;
    });
    await _save(reason: 'Ordre recalculé automatiquement');
  }

  Future<void> _save({
    String reason = 'Ordre modifié depuis les paramètres',
  }) async {
    final waitlist = _waitlist;
    if (waitlist == null || !_dirty) return;
    setState(() => _saving = true);
    try {
      final saved =
          await ref.read(sportWaitlistRepositoryProvider).reorderWaitlist(
                seasonId: waitlist.seasonId,
                orderedPlayerIds:
                    _entries.map((entry) => entry.seasonPlayerId).toList(),
                reason: reason,
              );
      if (!mounted) return;
      setState(() {
        _waitlist = saved;
        _entries = List.of(saved.entries);
        _dirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Liste d’attente enregistrée.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GrintaAppBar(
        title: const Text('Liste d’attente'),
        admin: widget.editable,
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loading || _saving ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _body(context),
      bottomNavigationBar: widget.editable
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                onPressed: _dirty && !_saving ? _save : null,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: GrintaProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Enregistrer l’ordre'),
              ),
            )
          : null,
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        if (widget.editable) ...[
          OutlinedButton.icon(
            onPressed: _saving ? null : _recalculateOrder,
            icon: const Icon(Icons.auto_fix_high_outlined),
            label: const Text('Recalculer'),
          ),
          const SizedBox(height: 14),
        ],
        _WaitlistTable(
          entries: _entries,
          editable: widget.editable,
          adjustingCounts: _adjustingCounts,
          onReorderDrop: _reorderByDrag,
          onIncrement: (entry) => _adjustWaitlistCount(entry, 1),
          onDecrement: (entry) => _adjustWaitlistCount(entry, -1),
        ),
      ],
    );
  }
}

class _WaitlistTable extends StatelessWidget {
  const _WaitlistTable({
    required this.entries,
    required this.editable,
    required this.adjustingCounts,
    required this.onReorderDrop,
    required this.onIncrement,
    required this.onDecrement,
  });

  final List<SportWaitlistEntry> entries;
  final bool editable;
  final Set<String> adjustingCounts;
  final void Function(SportWaitlistEntry dragged, SportWaitlistEntry target)
      onReorderDrop;
  final ValueChanged<SportWaitlistEntry> onIncrement;
  final ValueChanged<SportWaitlistEntry> onDecrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final borderColor = colors.outlineVariant;
    final headerColor = Color.alphaBlend(
      colors.primary.withAlpha(24),
      colors.surface,
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 92,
            color: headerColor,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _WaitlistCell(
                  width: 40,
                  borderColor: borderColor,
                  child: Text(
                    '#',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _WaitlistCell(
                  flex: 13,
                  borderColor: borderColor,
                  child: Text(
                    'Prénoms',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _WaitlistCell(
                  flex: 16,
                  borderColor: borderColor,
                  child: Text(
                    'Présence saison précédente',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _WaitlistCell(
                  flex: 21,
                  drawRightBorder: false,
                  borderColor: borderColor,
                  child: Text(
                    'Liste d’attente cette saison',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var index = 0; index < entries.length; index++)
            _WaitlistTableRow(
              key: ValueKey(entries[index].seasonPlayerId),
              index: index,
              entry: entries[index],
              editable: editable,
              adjustingCount:
                  adjustingCounts.contains(entries[index].seasonPlayerId),
              borderColor: borderColor,
              onReorderDrop: editable
                  ? (dragged) => onReorderDrop(dragged, entries[index])
                  : null,
              onIncrement: () => onIncrement(entries[index]),
              onDecrement: () => onDecrement(entries[index]),
            ),
        ],
      ),
    );
  }
}

class _WaitlistTableRow extends StatelessWidget {
  const _WaitlistTableRow({
    super.key,
    required this.index,
    required this.entry,
    required this.editable,
    required this.adjustingCount,
    required this.borderColor,
    required this.onIncrement,
    required this.onDecrement,
    this.onReorderDrop,
  });

  final int index;
  final SportWaitlistEntry entry;
  final bool editable;
  final bool adjustingCount;
  final Color borderColor;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final ValueChanged<SportWaitlistEntry>? onReorderDrop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final total = entry.previousSeasonMatchCount;
    final attendance = entry.previousSeasonAttendanceCount;
    final previousSeasonPresence = total > 0 ? '$attendance' : 'Aucune donnée';
    final waitlistCount = entry.currentSeasonWaitlistCount;
    final autoScroll = DragAutoScroller(context);

    Widget buildRow({bool highlighted = false}) {
      final content = AnimatedContainer(
        key: ValueKey('waitlist-row-${entry.seasonPlayerId}'),
        duration: const Duration(milliseconds: 120),
        height: 82,
        decoration: BoxDecoration(
          color: highlighted
              ? Color.alphaBlend(
                  colors.primary.withAlpha(18),
                  colors.surface,
                )
              : colors.surface,
          border: Border(top: BorderSide(color: borderColor)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WaitlistCell(
              width: 40,
              borderColor: borderColor,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _WaitlistCell(
              flex: 13,
              borderColor: borderColor,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                entry.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _WaitlistCell(
              flex: 16,
              borderColor: borderColor,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                previousSeasonPresence,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge,
              ),
            ),
            _WaitlistCell(
              flex: 21,
              drawRightBorder: false,
              borderColor: borderColor,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: editable
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            '$waitlistCount',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _CompactIconButton(
                          key: ValueKey(
                            'waitlist-decrement-${entry.seasonPlayerId}',
                          ),
                          icon: Icons.remove_circle_outline,
                          onPressed: !adjustingCount && waitlistCount > 0
                              ? onDecrement
                              : null,
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
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        ),
      );

      if (!editable) return content;

      return LongPressDraggable<SportWaitlistEntry>(
        key: ValueKey('waitlist-drag-${entry.seasonPlayerId}'),
        data: entry,
        feedback: Material(
          type: MaterialType.transparency,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 260),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(blurRadius: 12, color: Color(0x33000000)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${index + 1}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    entry.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: .3, child: content),
        onDragUpdate: (details) => autoScroll.update(details.globalPosition),
        onDragEnd: (_) => autoScroll.stop(),
        onDraggableCanceled: (_, __) => autoScroll.stop(),
        child: content,
      );
    }

    if (!editable || onReorderDrop == null) {
      return buildRow();
    }

    return DragTarget<SportWaitlistEntry>(
      onWillAcceptWithDetails: (details) =>
          details.data.seasonPlayerId != entry.seasonPlayerId,
      onAcceptWithDetails: (details) => onReorderDrop!(details.data),
      builder: (context, candidates, rejected) {
        return buildRow(highlighted: candidates.isNotEmpty);
      },
    );
  }
}

class _WaitlistCell extends StatelessWidget {
  const _WaitlistCell({
    required this.borderColor,
    required this.child,
    this.width,
    this.flex,
    this.drawRightBorder = true,
    this.alignment = Alignment.center,
    this.padding = const EdgeInsets.symmetric(horizontal: 8),
  }) : assert(width != null || flex != null);

  final double? width;
  final int? flex;
  final bool drawRightBorder;
  final Color borderColor;
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cell = Container(
      alignment: alignment,
      padding: padding,
      decoration: BoxDecoration(
        border: drawRightBorder
            ? Border(right: BorderSide(color: borderColor))
            : null,
      ),
      child: child,
    );

    if (width != null) {
      return SizedBox(width: width, child: cell);
    }
    return Expanded(flex: flex!, child: cell);
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
      constraints: const BoxConstraints.tightFor(width: 38, height: 44),
    );
  }
}
