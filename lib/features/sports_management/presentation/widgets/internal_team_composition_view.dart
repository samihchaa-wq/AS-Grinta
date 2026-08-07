import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/drag_auto_scroll.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/matches/domain/jersey_option.dart';
import 'package:as_grinta/features/sports_management/data/internal_match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/domain/internal_match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart'
    show PlayerAvatar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Composition d'un « match entre nous » : pas de terrain ni de formation,
/// juste une réserve de joueurs convoqués répartie en deux équipes identifiées
/// visuellement par les deux maillots de l'application.
class InternalTeamCompositionView extends ConsumerStatefulWidget {
  const InternalTeamCompositionView({
    super.key,
    required this.matchId,
    required this.editable,
  });

  final String matchId;
  final bool editable;

  @override
  ConsumerState<InternalTeamCompositionView> createState() =>
      _InternalTeamCompositionViewState();
}

class _InternalTeamCompositionViewState
    extends ConsumerState<InternalTeamCompositionView> {
  final _team1Controller = TextEditingController();
  final _team2Controller = TextEditingController();
  List<InternalCompositionEntry>? _entries;
  bool _dirty = false;
  bool _saving = false;

  @override
  void dispose() {
    _team1Controller.dispose();
    _team2Controller.dispose();
    super.dispose();
  }

  void _initFrom(InternalMatchComposition composition) {
    _team1Controller.text = composition.team1Name;
    _team2Controller.text = composition.team2Name;
    _entries = List.of(composition.entries);
  }

  void _moveTo(InternalCompositionEntry entry, int? teamNo) {
    setState(() {
      final entries = _entries;
      if (entries == null) return;
      final index = entries.indexWhere(
        (e) => e.participantId == entry.participantId,
      );
      if (index == -1) return;
      entries[index] = entries[index].copyWith(
        teamNo: teamNo,
        clearTeam: teamNo == null,
      );
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final entries = _entries;
    if (entries == null || _saving) return;
    setState(() => _saving = true);
    try {
      final saved =
          await ref.read(internalMatchCompositionRepositoryProvider).save(
        matchId: widget.matchId,
        team1Name: _team1Controller.text,
        team2Name: _team2Controller.text,
        entries: [
          for (final entry in entries.where((e) => e.teamNo == null)) entry,
          for (final entry in entries.where((e) => e.teamNo == 1)) entry,
          for (final entry in entries.where((e) => e.teamNo == 2)) entry,
        ],
      );
      if (!mounted) return;
      setState(() {
        _initFrom(saved);
        _dirty = false;
      });
      ref.invalidate(internalMatchCompositionProvider(widget.matchId));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Composition enregistrée.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(internalMatchCompositionProvider(widget.matchId));

    return async.when(
      loading: () => const Center(child: GrintaProgressIndicator()),
      error: (_, __) => const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Text('Composition indisponible.'),
        ),
      ),
      data: (composition) {
        if (composition == null) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('Match entre nous introuvable.'),
            ),
          );
        }
        _entries ??= List.of(composition.entries);
        if (!_dirty && _team1Controller.text.isEmpty) {
          _initFrom(composition);
        }
        final entries = _entries!;
        final unassigned = entries.where((e) => e.teamNo == null).toList();
        final team1 = entries.where((e) => e.teamNo == 1).toList();
        final team2 = entries.where((e) => e.teamNo == 2).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (unassigned.isNotEmpty || widget.editable) ...[
              Text(
                'Non affectés (${unassigned.length})',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              _TeamDropZone(
                teamNo: null,
                editable: widget.editable,
                onAccept: (entry) => _moveTo(entry, null),
                child: unassigned.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Aucun joueur à répartir.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in unassigned)
                            _PlayerChip(
                                entry: entry, editable: widget.editable),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _TeamColumn(
                    controller: widget.editable ? _team1Controller : null,
                    name: _team1Controller.text.isEmpty
                        ? composition.team1Name
                        : _team1Controller.text,
                    teamNo: 1,
                    entries: team1,
                    editable: widget.editable,
                    onAccept: (entry) => _moveTo(entry, 1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TeamColumn(
                    controller: widget.editable ? _team2Controller : null,
                    name: _team2Controller.text.isEmpty
                        ? composition.team2Name
                        : _team2Controller.text,
                    teamNo: 2,
                    entries: team2,
                    editable: widget.editable,
                    onAccept: (entry) => _moveTo(entry, 2),
                  ),
                ),
              ],
            ),
            if (widget.editable) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: GrintaProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Enregistrer la composition'),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TeamColumn extends StatelessWidget {
  const _TeamColumn({
    required this.name,
    required this.teamNo,
    required this.entries,
    required this.editable,
    required this.onAccept,
    this.controller,
  });

  final String name;
  final int teamNo;
  final List<InternalCompositionEntry> entries;
  final bool editable;
  final ValueChanged<InternalCompositionEntry> onAccept;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final jersey = teamNo == 1 ? JerseyOption.orange : JerseyOption.blue;
    final controllerName = controller?.text.trim();
    final semanticName = controllerName != null && controllerName.isNotEmpty
        ? controllerName
        : name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 88,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surface.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.outline.withValues(alpha: .3),
            ),
          ),
          child: Image.asset(
            jersey.assetPath,
            fit: BoxFit.contain,
            semanticLabel: '$semanticName, ${entries.length} joueurs',
          ),
        ),
        const SizedBox(height: 8),
        _TeamDropZone(
          teamNo: teamNo,
          editable: editable,
          onAccept: onAccept,
          child: entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Aucun joueur.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : Column(
                  children: [
                    for (final entry in entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _PlayerChip(
                          entry: entry,
                          editable: editable,
                          expand: true,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _TeamDropZone extends StatelessWidget {
  const _TeamDropZone({
    required this.teamNo,
    required this.editable,
    required this.onAccept,
    required this.child,
  });

  final int? teamNo;
  final bool editable;
  final ValueChanged<InternalCompositionEntry> onAccept;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!editable) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.outline.withValues(alpha: .3)),
        ),
        child: Padding(padding: const EdgeInsets.all(10), child: child),
      );
    }
    return DragTarget<InternalCompositionEntry>(
      onWillAcceptWithDetails: (details) => details.data.teamNo != teamNo,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidates, rejected) {
        final highlighted = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            color: highlighted
                ? AppTheme.accent.withValues(alpha: .18)
                : AppTheme.surface.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: highlighted
                  ? AppTheme.accent
                  : AppTheme.outline.withValues(alpha: .3),
              width: highlighted ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: child,
        );
      },
    );
  }
}

class _PlayerChip extends StatelessWidget {
  const _PlayerChip({
    required this.entry,
    required this.editable,
    this.expand = false,
  });

  final InternalCompositionEntry entry;
  final bool editable;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      width: expand ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.outline.withValues(alpha: .5)),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          PlayerAvatar(
            photoUrl: entry.photoUrl,
            name: entry.displayName,
            isGoalkeeper: entry.isGoalkeeper,
            size: 28,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              entry.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (!editable) return chip;
    final autoScroll = DragAutoScroller(context);
    return LongPressDraggable<InternalCompositionEntry>(
      data: entry,
      feedback: Material(type: MaterialType.transparency, child: chip),
      childWhenDragging: Opacity(opacity: .3, child: chip),
      onDragUpdate: (details) => autoScroll.update(details.globalPosition),
      onDragEnd: (_) => autoScroll.stop(),
      onDraggableCanceled: (_, __) => autoScroll.stop(),
      child: chip,
    );
  }
}
