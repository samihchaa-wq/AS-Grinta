import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/internal_matches/data/internal_matches_repository.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/players/data/roster_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class InternalMatchFormPage extends ConsumerStatefulWidget {
  const InternalMatchFormPage({super.key, this.match});

  final InternalMatch? match;

  @override
  ConsumerState<InternalMatchFormPage> createState() =>
      _InternalMatchFormPageState();
}

class _InternalMatchFormPageState
    extends ConsumerState<InternalMatchFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _teamAController = TextEditingController();
  final _teamBController = TextEditingController();
  final _addressController = TextEditingController();
  final _scoreAController = TextEditingController();
  final _scoreBController = TextEditingController();

  late String _seasonId;
  late DateTime _kickoffAt;
  final Map<String, int> _assignments = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final match = widget.match;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _seasonId = match?.seasonId ?? '';
    _kickoffAt = match?.kickoffAt ??
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 20, 30);
    _teamAController.text = match?.teamAName ?? 'Les Verts';
    _teamBController.text = match?.teamBName ?? 'Les Bleus';
    _addressController.text = match?.address ?? '';
    if (match?.scoreA != null) _scoreAController.text = '${match!.scoreA}';
    if (match?.scoreB != null) _scoreBController.text = '${match!.scoreB}';
    for (final player in match?.players ?? const <InternalMatchPlayer>[]) {
      _assignments[player.seasonPlayerId] = player.teamNo;
    }
  }

  @override
  void dispose() {
    _teamAController.dispose();
    _teamBController.dispose();
    _addressController.dispose();
    _scoreAController.dispose();
    _scoreBController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matchesState = ref.watch(matchesControllerProvider);
    final seasons = widget.match == null
        ? matchesState.seasons
            .where((season) => season['status']?.toString() == 'open')
            .toList()
        : matchesState.seasons;
    if (_seasonId.isEmpty && seasons.isNotEmpty) {
      _seasonId = seasons.first['id'].toString();
    }
    final rosterAsync = _seasonId.isEmpty
        ? const AsyncValue<List<RosterPlayer>>.data([])
        : ref.watch(rosterProvider(_seasonId));

    return Scaffold(
      appBar: GrintaAppBar(
        title: Text(
          widget.match == null
              ? 'Créer un match entre nous'
              : 'Modifier le match entre nous',
        ),
        admin: true,
        actions: [
          if (widget.match != null)
            IconButton(
              tooltip: 'Supprimer',
              onPressed: _saving ? null : _confirmDelete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Match interne',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Deux équipes composées librement. Ce match ne compte '
                      'dans aucun prono, vote HDM, classement ou statistique.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _seasonId.isEmpty ? null : _seasonId,
                      decoration: const InputDecoration(labelText: 'Saison'),
                      items: seasons
                          .map(
                            (season) => DropdownMenuItem<String>(
                              value: season['id'].toString(),
                              child: Text(season['name'].toString()),
                            ),
                          )
                          .toList(),
                      onChanged: widget.match != null
                          ? null
                          : (value) {
                              setState(() {
                                _seasonId = value ?? '';
                                _assignments.clear();
                              });
                            },
                      validator: (value) => value == null || value.isEmpty
                          ? 'Sélectionnez une saison'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _teamAController,
                            maxLength: 40,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Nom équipe A',
                              prefixIcon: Icon(Icons.shield_outlined),
                            ),
                            validator: _teamNameValidator,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _teamBController,
                            maxLength: 40,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Nom équipe B',
                              prefixIcon: Icon(Icons.shield_rounded),
                            ),
                            validator: _teamNameValidator,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Date'),
                      subtitle: Text(_formatDate(_kickoffAt)),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: _pickDate,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Heure'),
                      subtitle: Text(_formatTime(_kickoffAt)),
                      trailing: const Icon(Icons.schedule_outlined),
                      onTap: _pickTime,
                    ),
                    TextFormField(
                      controller: _addressController,
                      maxLength: 300,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Adresse (facultatif)',
                        hintText: 'Terrain, rue, ville…',
                        prefixIcon: Icon(Icons.place_outlined),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Score facultatif',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _scoreAController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: _teamAName,
                              hintText: '—',
                            ),
                            validator: _scoreValidator,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            '–',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextFormField(
                            controller: _scoreBController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: _teamBName,
                              hintText: '—',
                            ),
                            validator: _scoreValidator,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            rosterAsync.when(
              loading: () => const Card(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(humanizeError(error)),
                ),
              ),
              data: (allPlayers) {
                final players = allPlayers
                    .where((player) => player.isActive && !player.isCoach)
                    .toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AssignmentPanel(
                      players: players,
                      assignments: _assignments,
                      teamAName: _teamAName,
                      teamBName: _teamBName,
                      onChanged: (playerId, teamNo) {
                        setState(() {
                          if (teamNo == 0) {
                            _assignments.remove(playerId);
                          } else {
                            _assignments[playerId] = teamNo;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    _CompositionsPreview(
                      players: players,
                      assignments: _assignments,
                      teamAName: _teamAName,
                      teamBName: _teamBName,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Enregistrer le match entre nous'),
            ),
            if (widget.match != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: _saving ? null : _confirmDelete,
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Supprimer définitivement'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _teamAName {
    final value = _teamAController.text.trim();
    return value.isEmpty ? 'Équipe A' : value;
  }

  String get _teamBName {
    final value = _teamBController.text.trim();
    return value.isEmpty ? 'Équipe B' : value;
  }

  String? _teamNameValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Nom obligatoire';
    if (text.length > 40) return '40 caractères maximum';
    if (_teamAController.text.trim().toLowerCase() ==
        _teamBController.text.trim().toLowerCase()) {
      return 'Noms différents requis';
    }
    return null;
  }

  String? _scoreValidator(String? value) {
    final own = value?.trim() ?? '';
    final other = identical(value, _scoreAController.text)
        ? _scoreBController.text.trim()
        : _scoreAController.text.trim();
    if (own.isEmpty && other.isEmpty) return null;
    if (own.isEmpty || other.isEmpty) return 'Les 2 scores ensemble';
    final score = int.tryParse(own);
    if (score == null || score < 0 || score > 99) return '0 à 99';
    return null;
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _kickoffAt,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null) return;
    setState(() {
      _kickoffAt = DateTime(
        date.year,
        date.month,
        date.day,
        _kickoffAt.hour,
        _kickoffAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_kickoffAt),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null) return;
    setState(() {
      _kickoffAt = DateTime(
        _kickoffAt.year,
        _kickoffAt.month,
        _kickoffAt.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final teamAPlayers = _assignments.values.where((team) => team == 1).length;
    final teamBPlayers = _assignments.values.where((team) => team == 2).length;
    if (teamAPlayers == 0 || teamBPlayers == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ajoute au moins un joueur dans chaque équipe.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      var orderA = 0;
      var orderB = 0;
      final assignments = <InternalMatchAssignment>[];
      for (final entry in _assignments.entries) {
        if (entry.value == 1) {
          assignments.add(
            InternalMatchAssignment(
              seasonPlayerId: entry.key,
              teamNo: 1,
              sortOrder: orderA++,
            ),
          );
        } else if (entry.value == 2) {
          assignments.add(
            InternalMatchAssignment(
              seasonPlayerId: entry.key,
              teamNo: 2,
              sortOrder: orderB++,
            ),
          );
        }
      }
      final address = _addressController.text.trim();
      final scoreAText = _scoreAController.text.trim();
      final scoreBText = _scoreBController.text.trim();
      await ref.read(internalMatchesRepositoryProvider).save(
            matchId: widget.match?.id,
            seasonId: _seasonId,
            kickoffAt: _kickoffAt,
            teamAName: _teamAController.text.trim(),
            teamBName: _teamBController.text.trim(),
            address: address.isEmpty ? null : address,
            scoreA: scoreAText.isEmpty ? null : int.parse(scoreAText),
            scoreB: scoreBText.isEmpty ? null : int.parse(scoreBText),
            players: assignments,
          );
      ref.invalidate(internalMatchesProvider);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(humanizeError(error))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final match = widget.match;
    if (match == null) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Supprimer ce match entre nous ?'),
            content: const Text(
              'Les deux compositions et le score éventuel seront supprimés. '
              'Les statistiques officielles ne sont pas concernées.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Supprimer'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    setState(() => _saving = true);
    try {
      await ref.read(internalMatchesRepositoryProvider).delete(match.id);
      ref.invalidate(internalMatchesProvider);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(humanizeError(error))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  String _formatTime(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

class _AssignmentPanel extends StatelessWidget {
  const _AssignmentPanel({
    required this.players,
    required this.assignments,
    required this.teamAName,
    required this.teamBName,
    required this.onChanged,
  });

  final List<RosterPlayer> players;
  final Map<String, int> assignments;
  final String teamAName;
  final String teamBName;
  final void Function(String playerId, int teamNo) onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Répartir les joueurs',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              'Le nombre de joueurs est entièrement libre dans chaque équipe.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (players.isEmpty)
              const Text('Aucun joueur actif dans cette saison.')
            else
              for (final player in players)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 17,
                        backgroundImage: player.photoUrl == null
                            ? null
                            : NetworkImage(player.photoUrl!),
                        child: player.photoUrl == null
                            ? Text(
                                player.displayName.characters.first.toUpperCase(),
                              )
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          player.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      PopupMenuButton<int>(
                        tooltip: 'Choisir une équipe',
                        initialValue: assignments[player.id] ?? 0,
                        onSelected: (teamNo) => onChanged(player.id, teamNo),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 0,
                            child: Text('Non sélectionné'),
                          ),
                          PopupMenuItem(value: 1, child: Text(teamAName)),
                          PopupMenuItem(value: 2, child: Text(teamBName)),
                        ],
                        child: Chip(
                          avatar: Icon(
                            assignments[player.id] == 1
                                ? Icons.looks_one_outlined
                                : assignments[player.id] == 2
                                    ? Icons.looks_two_outlined
                                    : Icons.remove_circle_outline,
                            size: 18,
                          ),
                          label: Text(
                            switch (assignments[player.id]) {
                              1 => teamAName,
                              2 => teamBName,
                              _ => 'Non sélectionné',
                            },
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _CompositionsPreview extends StatelessWidget {
  const _CompositionsPreview({
    required this.players,
    required this.assignments,
    required this.teamAName,
    required this.teamBName,
  });

  final List<RosterPlayer> players;
  final Map<String, int> assignments;
  final String teamAName;
  final String teamBName;

  @override
  Widget build(BuildContext context) {
    final teamA = players.where((player) => assignments[player.id] == 1).toList();
    final teamB = players.where((player) => assignments[player.id] == 2).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _TeamCompositionCard(
            name: teamAName,
            players: teamA,
            icon: Icons.looks_one_outlined,
          ),
          _TeamCompositionCard(
            name: teamBName,
            players: teamB,
            icon: Icons.looks_two_outlined,
          ),
        ];
        if (constraints.maxWidth >= 700) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cards.first),
              const SizedBox(width: 12),
              Expanded(child: cards.last),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cards.first,
            const SizedBox(height: 12),
            cards.last,
          ],
        );
      },
    );
  }
}

class _TeamCompositionCard extends StatelessWidget {
  const _TeamCompositionCard({
    required this.name,
    required this.players,
    required this.icon,
  });

  final String name;
  final List<RosterPlayer> players;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  '${players.length}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: players.isEmpty
                ? const Text('Aucun joueur')
                : Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final player in players)
                        Chip(
                          avatar: player.isGoalkeeper
                              ? const Icon(Icons.sports_handball, size: 16)
                              : null,
                          label: Text(player.displayName),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
