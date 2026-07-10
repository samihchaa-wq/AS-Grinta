import 'package:as_grinta/features/matches/data/match_finalization_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MatchFinalizationPage extends ConsumerStatefulWidget {
  const MatchFinalizationPage({super.key, required this.matchId});
  final String matchId;

  @override
  ConsumerState<MatchFinalizationPage> createState() => _MatchFinalizationPageState();
}

class _MatchFinalizationPageState extends ConsumerState<MatchFinalizationPage> {
  final _grinta = TextEditingController();
  final _opponent = TextEditingController();
  final _guestName = TextEditingController();
  List<PostMatchPlayer>? _players;
  final _guests = <PostMatchGuest>[];
  String? _motm;
  bool _saving = false;

  @override
  void dispose() {
    _grinta.dispose();
    _opponent.dispose();
    _guestName.dispose();
    super.dispose();
  }

  void _changePlayer(int index, PostMatchPlayer player) {
    setState(() => _players![index] = player);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(matchFinalizationContextProvider(widget.matchId));
    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques du match')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('La feuille de match est indisponible.')),
        data: (data) {
          _players ??= [...data.players];
          final players = _players!;
          final presentPlayers = players.where((p) => p.present).toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Renseigne uniquement les statistiques après le match. Aucune composition ni saisie en direct.',
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: TextField(controller: _grinta, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Score Grinta'))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _opponent, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Score adverse'))),
              ]),
              const SizedBox(height: 20),
              Text('Joueurs', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              ...players.indexed.map((entry) {
                final index = entry.$1;
                final player = entry.$2;
                return Card(
                  child: ExpansionTile(
                    title: Text(player.name),
                    leading: Checkbox(
                      value: player.present,
                      onChanged: (value) => _changePlayer(index, player.copyWith(
                        present: value == true,
                        goals: value == true ? player.goals : 0,
                        assists: value == true ? player.assists : 0,
                        penaltyFaults: value == true ? player.penaltyFaults : 0,
                        cleanSheet: value == true ? player.cleanSheet : false,
                      )),
                    ),
                    subtitle: Text(player.present ? 'Présent' : 'Absent'),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: player.present ? [
                      _Counter(label: 'Buts', value: player.goals, onChanged: (v) => _changePlayer(index, player.copyWith(goals: v))),
                      _Counter(label: 'Passes décisives', value: player.assists, onChanged: (v) => _changePlayer(index, player.copyWith(assists: v))),
                      _Counter(label: 'Fautes provoquant un penalty', value: player.penaltyFaults, onChanged: (v) => _changePlayer(index, player.copyWith(penaltyFaults: v))),
                      if (player.isGoalkeeper)
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Clean sheet'),
                          value: player.cleanSheet,
                          onChanged: (v) => _changePlayer(index, player.copyWith(cleanSheet: v)),
                        ),
                    ] : const [],
                  ),
                );
              }),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: presentPlayers.any((p) => p.id == _motm) ? _motm : null,
                decoration: const InputDecoration(labelText: 'Homme du match (facultatif)'),
                items: presentPlayers.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                onChanged: (value) => setState(() => _motm = value),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: TextField(controller: _guestName, decoration: const InputDecoration(labelText: 'Invité du match'))),
                IconButton(
                  tooltip: 'Ajouter',
                  onPressed: () {
                    final name = _guestName.text.trim();
                    if (name.isEmpty) return;
                    setState(() {
                      _guests.add(PostMatchGuest(name: name));
                      _guestName.clear();
                    });
                  },
                  icon: const Icon(Icons.person_add_alt_1),
                ),
              ]),
              ..._guests.indexed.map((entry) {
                final index = entry.$1;
                final guest = entry.$2;
                return Card(
                  child: ExpansionTile(
                    title: Text('${guest.name} · Invité'),
                    trailing: IconButton(onPressed: () => setState(() => _guests.removeAt(index)), icon: const Icon(Icons.delete_outline)),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      _Counter(label: 'Buts', value: guest.goals, onChanged: (v) => setState(() => _guests[index] = guest.copyWith(goals: v))),
                      _Counter(label: 'Passes décisives', value: guest.assists, onChanged: (v) => setState(() => _guests[index] = guest.copyWith(assists: v))),
                      _Counter(label: 'Fautes provoquant un penalty', value: guest.penaltyFaults, onChanged: (v) => setState(() => _guests[index] = guest.copyWith(penaltyFaults: v))),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _saving ? null : () => _save(players),
                icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_circle_outline),
                label: const Text('Valider le résultat et les statistiques'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _save(List<PostMatchPlayer> players) async {
    final scoreGrinta = int.tryParse(_grinta.text);
    final scoreOpponent = int.tryParse(_opponent.text);
    if (scoreGrinta == null || scoreOpponent == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Renseigne les deux scores.')));
      return;
    }
    final goals = players.fold<int>(0, (sum, p) => sum + p.goals) + _guests.fold<int>(0, (sum, g) => sum + g.goals);
    if (goals != scoreGrinta) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Le total des buteurs ($goals) doit correspondre au score Grinta ($scoreGrinta).')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(matchFinalizationRepositoryProvider).finalize(
        matchId: widget.matchId,
        scoreGrinta: scoreGrinta,
        scoreOpponent: scoreOpponent,
        motmProfileId: _motm,
        players: players,
        guests: _guests,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La validation a échoué.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.label, required this.value, required this.onChanged});
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: Text(label)),
      IconButton(onPressed: value > 0 ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
      SizedBox(width: 30, child: Text('$value', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
      IconButton(onPressed: () => onChanged(value + 1), icon: const Icon(Icons.add_circle_outline)),
    ]);
  }
}
