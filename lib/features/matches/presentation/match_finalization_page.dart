import 'package:as_grinta/features/matches/data/match_finalization_repository.dart';
import 'package:as_grinta/features/matches/presentation/match_finalization_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MatchFinalizationPage extends ConsumerStatefulWidget {
  const MatchFinalizationPage({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<MatchFinalizationPage> createState() =>
      _MatchFinalizationPageState();
}

class _PlayerInput {
  bool present = false;
  int goals = 0;
  int assists = 0;
  int penaltyFaults = 0;
  bool cleanSheet = false;
}

class _GuestInput {
  final name = TextEditingController();
  final position = TextEditingController();
  bool present = true;
  int goals = 0;
  int assists = 0;
  int penaltyFaults = 0;

  void dispose() {
    name.dispose();
    position.dispose();
  }
}

class _MatchFinalizationPageState extends ConsumerState<MatchFinalizationPage> {
  final _opponentScoreController = TextEditingController(text: '0');
  final Map<String, _PlayerInput> _players = {};
  final List<_GuestInput> _guests = [];
  String? _motmProfileId;

  @override
  void dispose() {
    _opponentScoreController.dispose();
    for (final guest in _guests) {
      guest.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchFinalizationControllerProvider);
    final contextAsync =
        ref.watch(matchFinalizationContextProvider(widget.matchId));

    return Scaffold(
      appBar: AppBar(title: const Text('Feuille de match')),
      body: contextAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
        data: (sheet) {
          for (final player in sheet.players) {
            _players.putIfAbsent(player.id, _PlayerInput.new);
          }
          final computedScore = _players.values.fold<int>(
                0,
                (sum, item) => sum + item.goals,
              ) +
              _guests.fold<int>(0, (sum, item) => sum + item.goals);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'AS Grinta : $computedScore',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      SizedBox(
                        width: 130,
                        child: TextField(
                          controller: _opponentScoreController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Adversaire',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('Joueurs', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              ...sheet.players.map((player) {
                final input = _players[player.id]!;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ExpansionTile(
                    title: Text(player.name),
                    leading: Checkbox(
                      value: input.present,
                      onChanged: (value) => setState(() {
                        input.present = value ?? false;
                        if (!input.present) {
                          input.goals = 0;
                          input.assists = 0;
                          input.penaltyFaults = 0;
                          input.cleanSheet = false;
                          if (_motmProfileId == player.id) {
                            _motmProfileId = null;
                          }
                        }
                      }),
                    ),
                    subtitle: Text(
                      input.present
                          ? '⚽ ${input.goals}  👟 ${input.assists}  🟥 ${input.penaltyFaults}'
                          : 'Absent',
                    ),
                    children: [
                      _CounterRow(
                        label: '⚽ Buts',
                        value: input.goals,
                        enabled: input.present,
                        onChanged: (value) =>
                            setState(() => input.goals = value),
                      ),
                      _CounterRow(
                        label: '👟 Passes décisives',
                        value: input.assists,
                        enabled: input.present,
                        onChanged: (value) =>
                            setState(() => input.assists = value),
                      ),
                      _CounterRow(
                        label: '🟥 Faute provoquant un penalty',
                        value: input.penaltyFaults,
                        enabled: input.present,
                        onChanged: (value) =>
                            setState(() => input.penaltyFaults = value),
                      ),
                      if (player.isGoalkeeper)
                        SwitchListTile(
                          title: const Text('🧤 Clean sheet'),
                          value: input.cleanSheet,
                          onChanged: input.present
                              ? (value) =>
                                  setState(() => input.cleanSheet = value)
                              : null,
                        ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Invités du match',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => setState(() => _guests.add(_GuestInput())),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Ajouter'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (var index = 0; index < _guests.length; index++)
                _guestCard(index),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                value: _motmProfileId,
                decoration: const InputDecoration(
                  labelText: '⭐ Homme du match (facultatif)',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Aucun'),
                  ),
                  ...sheet.players
                      .where((player) => _players[player.id]!.present)
                      .map(
                        (player) => DropdownMenuItem<String?>(
                          value: player.id,
                          child: Text(player.name),
                        ),
                      ),
                ],
                onChanged: (value) => setState(() => _motmProfileId = value),
              ),
              if (state.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: state.isLoading ? null : () => _submit(sheet.players),
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Valider le résultat'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _guestCard(int index) {
    final guest = _guests[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: guest.name,
                    decoration: const InputDecoration(labelText: 'Nom'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: guest.position,
                    decoration: const InputDecoration(labelText: 'Poste'),
                  ),
                ),
                IconButton(
                  tooltip: 'Supprimer',
                  onPressed: () {
                    final removed = _guests.removeAt(index);
                    removed.dispose();
                    setState(() {});
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Présent'),
              value: guest.present,
              onChanged: (value) => setState(() => guest.present = value),
            ),
            _CounterRow(
              label: '⚽ Buts',
              value: guest.goals,
              enabled: guest.present,
              onChanged: (value) => setState(() => guest.goals = value),
            ),
            _CounterRow(
              label: '👟 Passes décisives',
              value: guest.assists,
              enabled: guest.present,
              onChanged: (value) => setState(() => guest.assists = value),
            ),
            _CounterRow(
              label: '🟥 Faute provoquant un penalty',
              value: guest.penaltyFaults,
              enabled: guest.present,
              onChanged: (value) =>
                  setState(() => guest.penaltyFaults = value),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(List<MatchSheetPlayer> players) async {
    final opponentScore = int.tryParse(_opponentScoreController.text.trim());
    if (opponentScore == null || opponentScore < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Score adverse invalide.')),
      );
      return;
    }
    for (final guest in _guests) {
      if (guest.name.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Le nom de chaque invité est requis.')),
        );
        return;
      }
    }

    final playerStats = players.map((player) {
      final input = _players[player.id]!;
      return {
        'profile_id': player.id,
        'present': input.present,
        'goals': input.goals,
        'assists': input.assists,
        'penalty_faults': input.penaltyFaults,
        'clean_sheet': player.isGoalkeeper && input.cleanSheet,
      };
    }).toList();
    final guestStats = _guests
        .map(
          (guest) => {
            'display_name': guest.name.text.trim(),
            'position': guest.position.text.trim().isEmpty
                ? 'Joueur'
                : guest.position.text.trim(),
            'present': guest.present,
            'goals': guest.goals,
            'assists': guest.assists,
            'penalty_faults': guest.penaltyFaults,
          },
        )
        .toList();

    final success = await ref
        .read(matchFinalizationControllerProvider.notifier)
        .finalizeMatch(
          matchId: widget.matchId,
          opponentScore: opponentScore,
          manOfTheMatchId: _motmProfileId,
          playerStats: playerStats,
          guestStats: guestStats,
        );
    if (success && mounted) Navigator.pop(context);
  }
}

class _CounterRow extends StatelessWidget {
  const _CounterRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: enabled && value > 0 ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(width: 28, child: Text('$value', textAlign: TextAlign.center)),
          IconButton(
            onPressed: enabled ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}
