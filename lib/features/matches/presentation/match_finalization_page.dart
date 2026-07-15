import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/home/data/home_repository.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/matches/data/match_finalization_repository.dart';
import 'package:as_grinta/features/matches/presentation/match_finalization_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Une ligne de but : un buteur (facultatif) et un nombre de buts pour ce
/// joueur sur cette ligne (case vide = 1).
class _GoalRow {
  _GoalRow({this.playerId, String count = ''})
      : countController = TextEditingController(text: count);

  String? playerId;
  final TextEditingController countController;

  void dispose() => countController.dispose();
}

/// Saisie complète d'un match : score, présents, buteurs, clean sheet et HDM.
/// Une correction recharge toutes les données déjà enregistrées.
class MatchFinalizationPage extends ConsumerStatefulWidget {
  const MatchFinalizationPage({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<MatchFinalizationPage> createState() =>
      _MatchFinalizationPageState();
}

class _MatchFinalizationPageState extends ConsumerState<MatchFinalizationPage> {
  final List<_GoalRow> _rows = [];
  final Set<String> _presentPlayerIds = {};
  int _grintaScore = 0;
  int _opponentScore = 0;
  bool _cleanSheet = false;
  bool _prefilled = false;
  String? _manOfMatchPlayerId;

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _prefillFrom(MatchFinalizationContext sheet) {
    if (_prefilled) return;
    _prefilled = true;

    final squadIds = sheet.squad.map((member) => member.id).toSet();
    _presentPlayerIds
      ..clear()
      ..addAll(
        sheet.presentPlayerIds.where(squadIds.contains),
      );
    if (sheet.manOfMatchPlayerId != null &&
        squadIds.contains(sheet.manOfMatchPlayerId)) {
      _manOfMatchPlayerId = sheet.manOfMatchPlayerId;
      _presentPlayerIds.add(sheet.manOfMatchPlayerId!);
    }

    if (!sheet.isValidated) return;
    _opponentScore = sheet.opponentScore;
    _grintaScore = sheet.grintaScore;
    _cleanSheet = sheet.cleanSheetProfileId != null &&
        sheet.cleanSheetProfileId == sheet.goalkeeperId;

    // Reconstitue les lignes à partir des buts déjà enregistrés (un buteur
    // avec 2 buts occupe une ligne « joueur × 2 »), puis complète avec des
    // lignes vides jusqu'à atteindre le score.
    final goalsByPlayer = <String, int>{};
    for (final id in sheet.scorerGoalLines) {
      goalsByPlayer.update(id, (v) => v + 1, ifAbsent: () => 1);
      if (squadIds.contains(id)) _presentPlayerIds.add(id);
    }
    for (final entry in goalsByPlayer.entries) {
      _rows.add(_GoalRow(playerId: entry.key, count: '${entry.value}'));
    }
    while (_rows.length < _grintaScore) {
      _rows.add(_GoalRow());
    }
    if (_cleanSheet && sheet.goalkeeperId != null) {
      _presentPlayerIds.add(sheet.goalkeeperId!);
    }
  }

  void _setGrintaScore(int value) {
    final next = value.clamp(0, 30);
    setState(() {
      while (_rows.length < next) {
        _rows.add(_GoalRow());
      }
      while (_rows.length > next) {
        _rows.removeLast().dispose();
      }
      _grintaScore = next;
    });
  }

  void _setAttendance(String playerId, bool isPresent) {
    setState(() {
      if (isPresent) {
        _presentPlayerIds.add(playerId);
      } else {
        _presentPlayerIds.remove(playerId);
        if (_manOfMatchPlayerId == playerId) {
          _manOfMatchPlayerId = null;
        }
      }
    });
  }

  void _selectAllPlayers(List<SquadMember> squad) {
    setState(() {
      _presentPlayerIds
        ..clear()
        ..addAll(squad.map((member) => member.id));
    });
  }

  void _clearAllPlayers() {
    setState(() {
      _presentPlayerIds.clear();
      _manOfMatchPlayerId = null;
      _cleanSheet = false;
    });
  }

  Future<void> _pickPlayer(int index, List<SquadMember> squad) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _PlayerPickerSheet(squad: squad),
    );
    if (selected != null) {
      setState(() {
        _rows[index].playerId = selected;
        _presentPlayerIds.add(selected);
      });
    }
  }

  Future<void> _submit(MatchFinalizationContext sheet) async {
    // Agrège les buts attribués par joueur (case vide = 1).
    final scorerGoals = <String, int>{};
    for (final row in _rows) {
      final id = row.playerId;
      if (id == null) continue;
      final parsed = int.tryParse(row.countController.text.trim());
      final goals = (parsed == null || parsed <= 0) ? 1 : parsed;
      scorerGoals.update(id, (v) => v + goals, ifAbsent: () => goals);
    }

    final cleanSheetId =
        _cleanSheet && _opponentScore == 0 ? sheet.goalkeeperId : null;
    final success = await ref
        .read(matchFinalizationControllerProvider.notifier)
        .finalizeMatch(
          matchId: widget.matchId,
          grintaScore: _grintaScore,
          opponentScore: _opponentScore,
          scorerGoals: scorerGoals,
          cleanSheetProfileId: cleanSheetId,
          presentPlayerIds: Set<String>.from(_presentPlayerIds),
          manOfMatchPlayerId: _manOfMatchPlayerId,
        );
    if (success) {
      ref.invalidate(matchDetailsProvider(widget.matchId));
      ref.invalidate(homeDashboardProvider);
      ref.invalidate(matchFinalizationContextProvider(widget.matchId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Match et statistiques enregistrés.')),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchFinalizationControllerProvider);
    final contextAsync =
        ref.watch(matchFinalizationContextProvider(widget.matchId));

    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Saisie du match')),
      body: contextAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(humanizeError(error), textAlign: TextAlign.center),
          ),
        ),
        data: (sheet) {
          _prefillFrom(sheet);
          final nameById = {for (final m in sheet.squad) m.id: m.name};
          final presentMembers = sheet.squad
              .where((member) => _presentPlayerIds.contains(member.id))
              .toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              _ScoreCard(
                grintaScore: _grintaScore,
                opponentScore: _opponentScore,
                onGrintaChanged: _setGrintaScore,
                onOpponentChanged: (value) => setState(() {
                  _opponentScore = value.clamp(0, 30);
                  if (_opponentScore > 0) _cleanSheet = false;
                }),
              ),
              const SizedBox(height: 20),
              _AttendanceCard(
                squad: sheet.squad,
                presentPlayerIds: _presentPlayerIds,
                onChanged: _setAttendance,
                onSelectAll: () => _selectAllPlayers(sheet.squad),
                onClearAll: _clearAllPlayers,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text(
                    'Buteurs',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _grintaScore == 0
                        ? ''
                        : '$_grintaScore ligne${_grintaScore > 1 ? 's' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _grintaScore == 0
                    ? 'Choisis le score d’AS Grinta pour ouvrir les lignes de '
                        'buteurs.'
                    : 'Un buteur par but (facultatif). Un buteur sélectionné '
                        'est automatiquement ajouté aux présents.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (var index = 0; index < _rows.length; index++)
                _ScorerRowTile(
                  key: ValueKey(_rows[index]),
                  index: index,
                  playerName: _rows[index].playerId == null
                      ? null
                      : nameById[_rows[index].playerId] ?? 'Joueur',
                  countController: _rows[index].countController,
                  onPick: () => _pickPlayer(index, sheet.squad),
                  onClear: _rows[index].playerId == null
                      ? null
                      : () => setState(() => _rows[index].playerId = null),
                ),
              const SizedBox(height: 20),
              if (sheet.goalkeeperId != null)
                Card(
                  child: SwitchListTile(
                    secondary: const Text('🧤', style: TextStyle(fontSize: 22)),
                    title: Text(
                      '${sheet.goalkeeperName ?? 'Le gardien'} a réalisé un '
                      'clean sheet',
                    ),
                    subtitle: _opponentScore > 0
                        ? const Text('Impossible : l’adversaire a marqué.')
                        : const Text(
                            'Le gardien sera automatiquement ajouté aux présents.',
                          ),
                    value: _cleanSheet && _opponentScore == 0,
                    onChanged: _opponentScore > 0
                        ? null
                        : (value) => setState(() {
                              _cleanSheet = value;
                              if (value) {
                                _presentPlayerIds.add(sheet.goalkeeperId!);
                              }
                            }),
                  ),
                ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: DropdownButtonFormField<String>(
                    value: _manOfMatchPlayerId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.star_outline),
                      labelText: 'Homme du match',
                      helperText: presentMembers.isEmpty
                          ? 'Sélectionne d’abord les joueurs présents.'
                          : 'Choisis le joueur élu pour ce match.',
                      suffixIcon: _manOfMatchPlayerId == null
                          ? null
                          : IconButton(
                              tooltip: 'Retirer le HDM',
                              onPressed: () =>
                                  setState(() => _manOfMatchPlayerId = null),
                              icon: const Icon(Icons.close),
                            ),
                    ),
                    items: [
                      for (final member in presentMembers)
                        DropdownMenuItem(
                          value: member.id,
                          child: Row(
                            children: [
                              Text(member.isGoalkeeper ? '🧤' : '⚽'),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  member.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    onChanged: presentMembers.isEmpty
                        ? null
                        : (value) =>
                            setState(() => _manOfMatchPlayerId = value),
                  ),
                ),
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
                onPressed: state.isLoading ? null : () => _submit(sheet),
                icon: state.isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  sheet.isValidated
                      ? 'Corriger le match'
                      : 'Enregistrer le match',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Le score, les présents et l’homme du match alimentent '
                'automatiquement les statistiques et les badges.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  const _AttendanceCard({
    required this.squad,
    required this.presentPlayerIds,
    required this.onChanged,
    required this.onSelectAll,
    required this.onClearAll,
  });

  final List<SquadMember> squad;
  final Set<String> presentPlayerIds;
  final void Function(String playerId, bool isPresent) onChanged;
  final VoidCallback onSelectAll;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Joueurs présents',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    '${presentPlayerIds.length}/${squad.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  TextButton(
                    onPressed: onSelectAll,
                    child: const Text('Tout sélectionner'),
                  ),
                  TextButton(
                    onPressed: presentPlayerIds.isEmpty ? null : onClearAll,
                    child: const Text('Effacer'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            for (final member in squad)
              CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.trailing,
                secondary: Text(
                  member.isGoalkeeper ? '🧤' : '⚽',
                  style: const TextStyle(fontSize: 20),
                ),
                title: Text(member.name),
                value: presentPlayerIds.contains(member.id),
                onChanged: (value) => onChanged(member.id, value ?? false),
              ),
          ],
        ),
      ),
    );
  }
}

/// Une ligne de buteur : bouton de sélection du joueur + petite case du nombre
/// de buts (vide = 1).
class _ScorerRowTile extends StatelessWidget {
  const _ScorerRowTile({
    super.key,
    required this.index,
    required this.playerName,
    required this.countController,
    required this.onPick,
    required this.onClear,
  });

  final int index;
  final String? playerName;
  final TextEditingController countController;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasPlayer = playerName != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 26,
            alignment: Alignment.center,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onPick,
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.outline),
                ),
                child: Row(
                  children: [
                    Text(
                      hasPlayer ? '⚽' : '➕',
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        hasPlayer ? playerName! : 'Choisir un buteur',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: hasPlayer
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (onClear != null)
                      GestureDetector(
                        onTap: onClear,
                        child: Icon(
                          Icons.close,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            child: TextField(
              controller: countController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontWeight: FontWeight.w800),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '1',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 6, vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Feuille de sélection d'un buteur avec recherche instantanée.
class _PlayerPickerSheet extends StatefulWidget {
  const _PlayerPickerSheet({required this.squad});

  final List<SquadMember> squad;

  @override
  State<_PlayerPickerSheet> createState() => _PlayerPickerSheetState();
}

class _PlayerPickerSheetState extends State<_PlayerPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final results = query.isEmpty
        ? widget.squad
        : widget.squad
            .where((m) => m.name.toLowerCase().contains(query))
            .toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Rechercher un buteur…',
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final member in results)
                  ListTile(
                    leading: Text(
                      member.isGoalkeeper ? '🧤' : '⚽',
                      style: const TextStyle(fontSize: 20),
                    ),
                    title: Text(member.name),
                    onTap: () => Navigator.pop(context, member.id),
                  ),
                if (results.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Aucun joueur trouvé.'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({
    required this.grintaScore,
    required this.opponentScore,
    required this.onGrintaChanged,
    required this.onOpponentChanged,
  });

  final int grintaScore;
  final int opponentScore;
  final ValueChanged<int> onGrintaChanged;
  final ValueChanged<int> onOpponentChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
        child: Row(
          children: [
            Expanded(
              child: _Stepper(
                label: 'AS Grinta',
                value: grintaScore,
                onChanged: onGrintaChanged,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '—',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            Expanded(
              child: _Stepper(
                label: 'Adversaire',
                value: opponentScore,
                onChanged: onOpponentChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

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
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              tooltip: 'Retirer un but',
              visualDensity: VisualDensity.compact,
              onPressed: value > 0 ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 40,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Ajouter un but',
              visualDensity: VisualDensity.compact,
              onPressed: () => onChanged(value + 1),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }
}
