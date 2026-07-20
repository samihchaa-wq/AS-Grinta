import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/sports_management/data/sport_waitlist_repository.dart';
import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AdminWaitlistPage extends ConsumerStatefulWidget {
  const AdminWaitlistPage({super.key});

  @override
  ConsumerState<AdminWaitlistPage> createState() => _AdminWaitlistPageState();
}

class _AdminWaitlistPageState extends ConsumerState<AdminWaitlistPage> {
  SportWaitlist? _waitlist;
  List<SportWaitlistEntry> _entries = const [];
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
      final value =
          await ref.read(sportWaitlistRepositoryProvider).fetchWaitlist();
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

  void _move(int index, int delta) {
    final next = index + delta;
    if (next < 0 || next >= _entries.length) return;
    setState(() {
      final entries = List<SportWaitlistEntry>.of(_entries);
      final item = entries.removeAt(index);
      entries.insert(next, item);
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
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loading || _saving ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _body(context),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: _dirty && !_saving ? _save : null,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Enregistrer l’ordre'),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
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
      return const Center(child: Text('Aucun joueur actif dans la saison.'));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saison ${waitlist.seasonName}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'L’application commence par le haut de cette liste lorsqu’il '
                  'faut proposer un joueur non convoqué. Cette proposition '
                  'reste entièrement modifiable pour chaque match.',
                ),
                const SizedBox(height: 8),
                Text(
                  'L’ordre initial utilise les présences de la saison '
                  'précédente. Seul un administrateur peut le modifier.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < _entries.length; index++)
          _WaitlistTile(
            index: index,
            entry: _entries[index],
            canMoveUp: index > 0,
            canMoveDown: index < _entries.length - 1,
            onMoveUp: () => _move(index, -1),
            onMoveDown: () => _move(index, 1),
          ),
      ],
    );
  }
}

class _WaitlistTile extends StatelessWidget {
  const _WaitlistTile({
    required this.index,
    required this.entry,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final int index;
  final SportWaitlistEntry entry;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    final total = entry.previousSeasonMatchCount;
    final attendance = entry.previousSeasonAttendanceCount;
    return Card(
      key: ValueKey(entry.seasonPlayerId),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(child: Text('${index + 1}')),
        title: Text(
          entry.displayName,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          total > 0
              ? '$attendance présence${attendance > 1 ? 's' : ''} sur '
                  '$total match${total > 1 ? 's' : ''} la saison dernière'
              : 'Aucune référence de présence la saison dernière',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            InkWell(
              onTap: canMoveUp ? onMoveUp : null,
              child: Icon(
                Icons.keyboard_arrow_up,
                color: canMoveUp ? null : Theme.of(context).disabledColor,
              ),
            ),
            InkWell(
              onTap: canMoveDown ? onMoveDown : null,
              child: Icon(
                Icons.keyboard_arrow_down,
                color: canMoveDown ? null : Theme.of(context).disabledColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
