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
  /// joueurs les moins présents la saison précédente.
  void _recalculateOrder() {
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
  }

  Future<void> _save() async {
    final waitlist = _waitlist;
    if (waitlist == null || !_dirty) return;
    setState(() => _saving = true);
    try {
      final saved =
          await ref.read(sportWaitlistRepositoryProvider).reorderWaitlist(
                seasonId: waitlist.seasonId,
                orderedPlayerIds:
                    _entries.map((entry) => entry.seasonPlayerId).toList(),
                reason: 'Ordre modifié depuis les paramètres',
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
            onPressed: _recalculateOrder,
            icon: const Icon(Icons.auto_fix_high_outlined),
            label: const Text('Recalculer'),
          ),
          const SizedBox(height: 10),
        ],
        for (var index = 0; index < _entries.length; index++)
          _WaitlistTile(
            key: ValueKey(_entries[index].seasonPlayerId),
            index: index,
            entry: _entries[index],
            editable: widget.editable,
            adjustingCount:
                _adjustingCounts.contains(_entries[index].seasonPlayerId),
            onReorderDrop: widget.editable
                ? (dragged) => _reorderByDrag(dragged, _entries[index])
                : null,
            onIncrement: () => _adjustWaitlistCount(_entries[index], 1),
            onDecrement: () => _adjustWaitlistCount(_entries[index], -1),
          ),
      ],
    );
  }
}

class _WaitlistTile extends StatelessWidget {
  const _WaitlistTile({
    super.key,
    required this.index,
    required this.entry,
    required this.editable,
    required this.adjustingCount,
    required this.onIncrement,
    required this.onDecrement,
    this.onReorderDrop,
  });

  final int index;
  final SportWaitlistEntry entry;

  /// Faux pour l'écran joueur (lecture seule) : masque le glisser-déposer
  /// de réordonnancement et les boutons +/- du nombre de fois en liste
  /// d'attente.
  final bool editable;
  final bool adjustingCount;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  /// Appelé avec le joueur glissé quand il est déposé sur cette puce, pour
  /// le repositionner à cet emplacement dans la liste.
  final ValueChanged<SportWaitlistEntry>? onReorderDrop;

  @override
  Widget build(BuildContext context) {
    final total = entry.previousSeasonMatchCount;
    final attendance = entry.previousSeasonAttendanceCount;
    final previousSeasonPresence = total > 0 ? '$attendance' : 'Aucune donnée';
    final waitlistCount = entry.currentSeasonWaitlistCount;
    final waitlistCountText =
        Text('Liste d’attente cette saison : $waitlistCount fois');
    final autoScroll = DragAutoScroller(context);

    Widget? trailing;
    if (editable) {
      final handle = Icon(Icons.drag_indicator, color: Theme.of(context).hintColor);
      trailing = LongPressDraggable<SportWaitlistEntry>(
        data: entry,
        feedback: Material(
          type: MaterialType.transparency,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(blurRadius: 12, color: Color(0x33000000)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.drag_indicator,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  entry.displayName,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: .3, child: handle),
        onDragUpdate: (details) => autoScroll.update(details.globalPosition),
        onDragEnd: (_) => autoScroll.stop(),
        onDraggableCanceled: (_, __) => autoScroll.stop(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: handle,
        ),
      );
    }

    final card = Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
        minLeadingWidth: 30,
        horizontalTitleGap: 12,
        leading: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.primaryContainer,
          ),
          child: Text(
            '${index + 1}',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
          ),
        ),
        title: Text(
          entry.displayName,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 3),
            Text('Présence saison précédente : $previousSeasonPresence'),
            if (editable)
              Row(
                children: [
                  Expanded(child: waitlistCountText),
                  _CompactIconButton(
                    icon: Icons.remove_circle_outline,
                    onPressed: !adjustingCount && waitlistCount > 0
                        ? onDecrement
                        : null,
                  ),
                  _CompactIconButton(
                    icon: Icons.add_circle_outline,
                    onPressed: adjustingCount ? null : onIncrement,
                  ),
                ],
              )
            else
              waitlistCountText,
          ],
        ),
        trailing: trailing,
      ),
    );

    if (!editable || onReorderDrop == null) {
      return card;
    }

    return DragTarget<SportWaitlistEntry>(
      onWillAcceptWithDetails: (details) =>
          details.data.seasonPlayerId != entry.seasonPlayerId,
      onAcceptWithDetails: (details) => onReorderDrop!(details.data),
      builder: (context, candidates, rejected) {
        final highlighted = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: highlighted
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: card,
        );
      },
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
    );
  }
}
