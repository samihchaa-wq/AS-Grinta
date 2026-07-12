import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/matches/data/match_finalization_repository.dart';
import 'package:as_grinta/features/matches/presentation/match_finalization_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Saisie d'un match en une vingtaine de secondes : score adverse, buteurs
/// (recherche instantanée, focus conservé), clean sheet du gardien.
class MatchFinalizationPage extends ConsumerStatefulWidget {
  const MatchFinalizationPage({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<MatchFinalizationPage> createState() =>
      _MatchFinalizationPageState();
}

class _MatchFinalizationPageState extends ConsumerState<MatchFinalizationPage> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  /// Un identifiant de buteur par but marqué (dans l'ordre de saisie).
  final List<String> _goalLines = [];
  int _opponentScore = 0;
  bool _cleanSheet = false;
  String _query = '';
  bool _prefilled = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _prefillFrom(MatchFinalizationContext sheet) {
    if (_prefilled) return;
    _prefilled = true;
    if (!sheet.isValidated) return;
    _opponentScore = sheet.opponentScore;
    _goalLines.addAll(sheet.scorerGoalLines);
    _cleanSheet = sheet.cleanSheetProfileId != null &&
        sheet.cleanSheetProfileId == sheet.goalkeeperId;
  }

  void _addGoal(String profileId) {
    setState(() {
      _goalLines.add(profileId);
      _searchController.clear();
      _query = '';
    });
    // Le clavier reste ouvert pour enchaîner le buteur suivant.
    _searchFocus.requestFocus();
  }

  void _removeGoalAt(int index) {
    setState(() => _goalLines.removeAt(index));
  }

  Future<void> _submit(MatchFinalizationContext sheet) async {
    final cleanSheetId =
        _cleanSheet && _opponentScore == 0 ? sheet.goalkeeperId : null;
    final success =
        await ref.read(matchFinalizationControllerProvider.notifier).finalizeMatch(
              matchId: widget.matchId,
              opponentScore: _opponentScore,
              scorerProfileIds: _goalLines,
              cleanSheetProfileId: cleanSheetId,
            );
    if (success) {
      ref.invalidate(matchDetailsProvider(widget.matchId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Match enregistré.')),
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
      appBar: AppBar(title: const Text('Saisie du match')),
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
          final grintaScore = _goalLines.length;
          final nameById = {for (final m in sheet.squad) m.id: m.name};

          final query = _query.trim().toLowerCase();
          final suggestions = query.isEmpty
              ? const <SquadMember>[]
              : sheet.squad
                  .where((m) => m.name.toLowerCase().contains(query))
                  .take(6)
                  .toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              _ScoreCard(
                grintaScore: grintaScore,
                opponentScore: _opponentScore,
                onOpponentChanged: (value) => setState(() {
                  _opponentScore = value;
                  if (_opponentScore > 0) _cleanSheet = false;
                }),
              ),
              const SizedBox(height: 20),
              Text('Buteurs', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                autofocus: !sheet.isValidated,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Rechercher un buteur…',
                  border: const OutlineInputBorder(),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _query = '';
                            });
                            _searchFocus.requestFocus();
                          },
                        )
                      : null,
                ),
                onChanged: (value) => setState(() => _query = value),
                onSubmitted: (_) {
                  if (suggestions.isNotEmpty) _addGoal(suggestions.first.id);
                },
              ),
              if (suggestions.isNotEmpty)
                Card(
                  margin: const EdgeInsets.only(top: 4),
                  child: Column(
                    children: [
                      for (final member in suggestions)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            member.isGoalkeeper
                                ? Icons.sports_handball
                                : Icons.sports_soccer,
                          ),
                          title: Text(member.name),
                          trailing: const Icon(Icons.add_circle_outline),
                          onTap: () => _addGoal(member.id),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              if (_goalLines.isEmpty)
                Text(
                  'Aucun but pour l’instant.',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              else
                for (var index = 0; index < _goalLines.length; index++)
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      leading: const Text('⚽', style: TextStyle(fontSize: 20)),
                      title: Text(
                        nameById[_goalLines[index]] ?? 'Joueur',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Retirer ce but',
                        onPressed: () => _removeGoalAt(index),
                      ),
                    ),
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
                        ? const Text(
                            'Impossible : l’adversaire a marqué.',
                          )
                        : const Text('Oui / Non'),
                    value: _cleanSheet && _opponentScore == 0,
                    onChanged: _opponentScore > 0
                        ? null
                        : (value) => setState(() => _cleanSheet = value),
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
                  sheet.isValidated ? 'Corriger le match' : 'Enregistrer le match',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Le score d’AS Grinta ($grintaScore) est calculé à partir des '
                'buts. L’enregistrement publie le résultat et les points sans '
                'archiver le match : tu peux corriger quand tu veux.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'AS Grinta',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$grintaScore',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Calculé avec les buts',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child:
                  Text('—', style: Theme.of(context).textTheme.headlineMedium),
            ),
            Expanded(
              child: Column(
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
                        onPressed: opponentScore > 0
                            ? () => onOpponentChanged(opponentScore - 1)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text(
                          '$opponentScore',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Ajouter un but',
                        onPressed: () => onOpponentChanged(opponentScore + 1),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
