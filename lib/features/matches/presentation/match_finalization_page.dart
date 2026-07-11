import 'package:as_grinta/features/matches/data/match_details_repository.dart';
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
  final Map<String, _PlayerInput> _players = {};
  final List<_GuestInput> _guests = [];
  int _opponentScore = 0;
  String? _motmProfileId;
  bool _prefilled = false;

  void _prefillFrom(MatchFinalizationContext sheet) {
    if (_prefilled) return;
    _prefilled = true;
    if (!sheet.isValidated) return;

    _opponentScore = sheet.opponentScore;
    _motmProfileId = sheet.motmProfileId;
    for (final entry in sheet.existingPlayerStats.entries) {
      _players[entry.key] = _PlayerInput()
        ..present = entry.value.present
        ..goals = entry.value.goals
        ..assists = entry.value.assists
        ..penaltyFaults = entry.value.penaltyFaults
        ..cleanSheet = entry.value.cleanSheet;
    }
    for (final guest in sheet.existingGuests) {
      final input = _GuestInput()
        ..present = guest.present
        ..goals = guest.goals
        ..assists = guest.assists
        ..penaltyFaults = guest.penaltyFaults;
      input.name.text = guest.name;
      input.position.text = guest.position;
      _guests.add(input);
    }
  }

  @override
  void dispose() {
    for (final guest in _guests) {
      guest.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchFinalizationControllerProvider);
    final contextAsync = ref.watch(
      matchFinalizationContextProvider(widget.matchId),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Feuille de match')),
      body: contextAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
        data: (sheet) {
          _prefillFrom(sheet);
          for (final player in sheet.players) {
            _players.putIfAbsent(player.id, _PlayerInput.new);
          }
          final computedScore =
              _players.values.fold<int>(0, (sum, item) => sum + item.goals) +
              _guests.fold<int>(0, (sum, item) => sum + item.goals);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              _ScoreCard(
                grintaScore: computedScore,
                opponentScore: _opponentScore,
                onOpponentChanged: (value) {
                  setState(() => _opponentScore = value);
                },
              ),
              const SizedBox(height: 20),
              Text('Joueurs', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              ...sheet.players.map((player) {
                final input = _players[player.id]!;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                    childrenPadding: const EdgeInsets.only(bottom: 8),
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
                          ? '⚽ ${input.goals}  👟 ${input.assists}  ⚠️ ${input.penaltyFaults}'
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
                        label: '⚠️ Faute provoquant un penalty',
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
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  Text(
                    'Invités du match',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => setState(() => _guests.add(_GuestInput())),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Ajouter'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (var index = 0; index < _guests.length; index++)
                _guestCard(index),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                initialValue: _motmProfileId,
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
                onPressed: state.isLoading
                    ? null
                    : () => _submit(sheet.players),
                icon: const Icon(Icons.verified_outlined),
                label: Text(
                  sheet.isValidated
                      ? 'Corriger le résultat'
                      : 'Valider le résultat',
                ),
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
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 520;
                final fields = [
                  TextField(
                    controller: guest.name,
                    decoration: const InputDecoration(labelText: 'Nom'),
                  ),
                  TextField(
                    controller: guest.position,
                    decoration: const InputDecoration(labelText: 'Poste'),
                  ),
                ];

                if (compact) {
                  return Column(
                    children: [
                      fields[0],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: fields[1]),
                          IconButton(
                            tooltip: 'Supprimer',
                            onPressed: () => _removeGuest(index),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: fields[0]),
                    const SizedBox(width: 8),
                    Expanded(child: fields[1]),
                    IconButton(
                      tooltip: 'Supprimer',
                      onPressed: () => _removeGuest(index),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                );
              },
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
              label: '⚠️ Faute provoquant un penalty',
              value: guest.penaltyFaults,
              enabled: guest.present,
              onChanged: (value) => setState(() => guest.penaltyFaults = value),
            ),
          ],
        ),
      ),
    );
  }

  void _removeGuest(int index) {
    final removed = _guests.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  Future<void> _submit(List<MatchSheetPlayer> players) async {
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
          opponentScore: _opponentScore,
          manOfTheMatchId: _motmProfileId,
          playerStats: playerStats,
          guestStats: guestStats,
        );
    if (success) {
      ref.invalidate(matchDetailsProvider(widget.matchId));
      if (mounted) Navigator.pop(context);
    }
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({
    required this.grintaScore,
    required this.opponentScore,
    required this.onOpponentChanged,
  });

  final int grintaScore;
  final int opponentScore;
  final ValueChanged<int> onOpponentChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        child: Row(
          children: [
            Expanded(
              child: _TeamScore(
                label: 'AS Grinta',
                score: grintaScore,
                helper: 'Calculé avec les buts',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '—',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            Expanded(
              child: _OpponentScoreStepper(
                score: opponentScore,
                onChanged: onOpponentChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamScore extends StatelessWidget {
  const _TeamScore({
    required this.label,
    required this.score,
    required this.helper,
  });

  final String label;
  final int score;
  final String helper;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          '$score',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 4),
        Text(
          helper,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _OpponentScoreStepper extends StatelessWidget {
  const _OpponentScoreStepper({
    required this.score,
    required this.onChanged,
  });

  final int score;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Adversaire',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              tooltip: 'Retirer un but',
              onPressed: score > 0 ? () => onChanged(score - 1) : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 48,
              child: Text(
                '$score',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Ajouter un but',
              onPressed: () => onChanged(score + 1),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Saisie manuelle',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            onPressed: enabled && value > 0 ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 32,
            child: Text('$value', textAlign: TextAlign.center),
          ),
          IconButton(
            onPressed: enabled ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}
