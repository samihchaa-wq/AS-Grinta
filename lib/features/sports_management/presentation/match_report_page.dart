import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_sport_report_repository.dart';
import 'package:as_grinta/features/sports_management/data/sport_match_finalization_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/match_goal_action.dart';
import 'package:as_grinta/features/sports_management/domain/match_report_score_sync.dart';
import 'package:as_grinta/features/sports_management/domain/match_sport_report.dart';
import 'package:as_grinta/features/sports_management/domain/match_squad_editing.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/match_goal_actions_editor.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/match_squad_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Écran « Compte rendu » : deux onglets, une seule validation.
///
/// Il sert aux trois cas : saisir un match terminé sans suivi en direct,
/// corriger le récapitulatif après un Live, et corriger un match déjà validé
/// pendant la fenêtre de correction. On passe librement d'un onglet à l'autre
/// sans rien perdre : tout reste local jusqu'au bouton du bas.
class MatchReportPage extends ConsumerWidget {
  const MatchReportPage({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: GrintaAppBar(
        title: const Text('Compte rendu'),
        admin: true,
      ),
      body: MatchReportView(matchId: matchId),
    );
  }
}

/// Le compte rendu sans échafaudage de page : le Tableau Blanc l'insère
/// directement dans son onglet une fois le match terminé.
class MatchReportView extends ConsumerStatefulWidget {
  const MatchReportView({
    super.key,
    required this.matchId,
    this.onPublished,
  });

  final String matchId;
  final VoidCallback? onPublished;

  @override
  ConsumerState<MatchReportView> createState() => _MatchReportViewState();
}

class _MatchReportViewState extends ConsumerState<MatchReportView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  MatchSportReport? _report;
  MatchComposition? _lineup;
  List<MatchGoalAction> _goals = const [];
  int _scoreAsGrinta = 0;
  int _scoreAdverse = 0;
  int _localKeySeed = 0;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await ref
          .read(matchSportReportRepositoryProvider)
          .fetch(widget.matchId);
      if (!mounted) return;
      setState(() => _adopt(report));
    } catch (error) {
      if (mounted) setState(() => _error = humanizeError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Reprend l'état serveur, en complétant les faits manquants : un match
  /// terminé sans Live arrive avec un score et aucun but, il faut donc créer
  /// les buts à compléter.
  void _adopt(MatchSportReport report) {
    _report = report;
    _lineup = report.lineup;
    _scoreAsGrinta = report.finalization.scoreAsGrinta;
    _scoreAdverse = report.finalization.scoreAdverse;
    _goals = sortChronologically(report.goalActions);
    final plan = planScoreChange(
      goalActions: _goals,
      scoreAsGrinta: _scoreAsGrinta,
      scoreAdverse: _scoreAdverse,
    );
    if (plan.asGrintaToAdd > 0 || plan.opponentToAdd > 0) {
      _goals = addMissingGoals(
        goalActions: _goals,
        plan: plan,
        nextLocalKey: () => _localKeySeed++,
      );
    }
    // Si les faits enregistrés dépassent le score (cas historique), le score
    // suit les faits : ils sont la référence.
    if (plan.asGrintaToRemove > 0) {
      _scoreAsGrinta = countGoals(_goals, MatchGoalTeamSide.asGrinta);
    }
    if (plan.opponentToRemove > 0) {
      _scoreAdverse = countGoals(_goals, MatchGoalTeamSide.opponent);
    }
  }

  bool get _editable => _report?.isEditable ?? false;

  List<MatchCompositionEntry> get _squad =>
      _lineup == null ? const [] : squadEntries(_lineup!);

  Set<String> get _squadIds =>
      {for (final entry in _squad) entry.participantId};

  // ------------------------------------------------------------- effectif

  void _updateLineup(MatchComposition next) {
    setState(() {
      _lineup = next;
      // Un joueur qui n'est plus dans l'effectif perd ses attributions, mais
      // son but reste au score.
      final present = {
        for (final entry in squadEntries(next)) entry.participantId,
      };
      for (final goal in _goals) {
        final scorer = goal.scorerParticipantId;
        final assist = goal.assistParticipantId;
        if (scorer != null && !present.contains(scorer)) {
          _goals = detachParticipant(
            goalActions: _goals,
            participantId: scorer,
          );
        }
        if (assist != null && !present.contains(assist)) {
          _goals = detachParticipant(
            goalActions: _goals,
            participantId: assist,
          );
        }
      }
    });
  }

  void _dropOnSlot(MatchCompositionEntry moving, slot) {
    final lineup = _lineup;
    if (lineup == null || !_editable) return;
    if (wouldExceedStarterLimit(lineup, moving) &&
        !_slotIsOccupied(lineup, slot)) {
      _showMessage('Il ne peut pas y avoir plus de $kMaxStarters titulaires.');
      return;
    }
    _updateLineup(placeEntryOnSlot(lineup, moving, slot));
  }

  bool _slotIsOccupied(MatchComposition lineup, slot) {
    return lineup.entriesFor(MatchCompositionZone.field).any(
          (entry) =>
              (Offset(entry.x ?? .5, entry.y ?? .5) - slot.position).distance <
              .12,
        );
  }

  void _moveToBench(MatchCompositionEntry moving) {
    final lineup = _lineup;
    if (lineup == null || !_editable) return;
    _updateLineup(moveEntryToBench(lineup, moving));
  }

  void _removeFromSquad(MatchCompositionEntry moving) {
    final lineup = _lineup;
    if (lineup == null || !_editable) return;
    _updateLineup(removeEntryFromSquad(lineup, moving));
  }

  void _changeFormation(String formationCode) {
    final lineup = _lineup;
    if (lineup == null || !_editable) return;
    try {
      _updateLineup(repositionForFormation(lineup, formationCode));
    } on StateError catch (error) {
      _showMessage(error.message);
    }
  }

  // --------------------------------------------------------------- score

  Future<void> _changeScore({required bool asGrinta, required int next}) async {
    if (!_editable || _saving) return;
    final side =
        asGrinta ? MatchGoalTeamSide.asGrinta : MatchGoalTeamSide.opponent;
    final current = countGoals(_goals, side);
    if (next == current) return;

    if (next > current) {
      final plan = planScoreChange(
        goalActions: _goals,
        scoreAsGrinta: asGrinta ? next : _scoreAsGrinta,
        scoreAdverse: asGrinta ? _scoreAdverse : next,
      );
      setState(() {
        _goals = addMissingGoals(
          goalActions: _goals,
          plan: plan,
          nextLocalKey: () => _localKeySeed++,
        );
        if (asGrinta) {
          _scoreAsGrinta = next;
        } else {
          _scoreAdverse = next;
        }
      });
      return;
    }

    // Le score baisse : on ne supprime jamais un but au hasard.
    final removed = await _askWhichGoalsToRemove(
      side: side,
      count: current - next,
    );
    if (removed == null || !mounted) return;
    setState(() {
      _goals = removeGoals(goalActions: _goals, localKeys: removed);
      if (asGrinta) {
        _scoreAsGrinta = next;
      } else {
        _scoreAdverse = next;
      }
    });
  }

  Future<Set<String>?> _askWhichGoalsToRemove({
    required MatchGoalTeamSide side,
    required int count,
  }) {
    final candidates = _goals.where((goal) => goal.teamSide == side).toList();
    final selected = <String>{};
    return showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(
            count == 1
                ? 'Quel but souhaitez-vous supprimer ?'
                : 'Quels $count buts souhaitez-vous supprimer ?',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final goal in candidates)
                  CheckboxListTile(
                    dense: true,
                    value: selected.contains(goal.localKey),
                    onChanged: (checked) => setDialogState(() {
                      if (checked == true) {
                        if (selected.length < count) {
                          selected.add(goal.localKey);
                        }
                      } else {
                        selected.remove(goal.localKey);
                      }
                    }),
                    title: Text(_goalLabel(goal)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: selected.length == count
                  ? () => Navigator.pop(dialogContext, {...selected})
                  : null,
              child: const Text('Supprimer'),
            ),
          ],
        ),
      ),
    );
  }

  String _goalLabel(MatchGoalAction goal) {
    final minute = goal.minute == null ? 'Minute inconnue' : "${goal.minute}'";
    if (!goal.isAsGrinta) {
      return '$minute · ${goal.isOwnGoal ? 'CSC AS Grinta' : _opponentName}';
    }
    if (goal.isOwnGoal) return '$minute · CSC adverse';
    return '$minute · ${goal.scorerName ?? 'Buteur non attribué'}';
  }

  String get _opponentName => _report?.opponentName ?? 'Adversaire';

  // ------------------------------------------------------- faits du match

  void _updateGoal(MatchGoalAction updated) {
    setState(() {
      _goals = [
        for (final goal in _goals)
          if (goal.localKey == updated.localKey) updated else goal,
      ];
    });
  }

  void _reorderGoals(int oldIndex, int newIndex) {
    setState(() {
      _goals = moveGoal(
        goalActions: _goals,
        oldIndex: oldIndex,
        newIndex: newIndex,
      );
    });
  }

  // ---------------------------------------------------------- validation

  String? get _squadIssue {
    final lineup = _lineup;
    if (lineup == null) return 'Effectif indisponible.';
    final field = lineup.entriesFor(MatchCompositionZone.field).length;
    if (field > kMaxStarters) {
      return 'Il ne peut pas y avoir plus de $kMaxStarters titulaires.';
    }
    if (_squad.isEmpty) {
      return 'Place au moins un joueur sur le terrain ou le banc.';
    }
    return null;
  }

  String? get _factsIssue => validateGoalActions(
        goalActions: _goals,
        scoreAsGrinta: _scoreAsGrinta,
        scoreAdverse: _scoreAdverse,
        squadParticipantIds: _squadIds,
      );

  Future<void> _submit() async {
    final report = _report;
    final lineup = _lineup;
    if (report == null || lineup == null || _saving) return;
    final issue = _squadIssue ?? _factsIssue;
    if (issue != null) {
      _showMessage(issue);
      return;
    }

    final unattributed = _goals.where((goal) => goal.hasUnknownScorer).length;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              report.isCorrection
                  ? 'Corriger le compte rendu ?'
                  : 'Valider le compte rendu ?',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AS Grinta $_scoreAsGrinta – $_scoreAdverse $_opponentName · '
                    '${lineup.entriesFor(MatchCompositionZone.field).length} '
                    'titulaires · '
                    '${lineup.entriesFor(MatchCompositionZone.bench).length} '
                    'remplaçants.',
                  ),
                  if (unattributed > 0) ...[
                    const SizedBox(height: 10),
                    Text(
                      unattributed == 1
                          ? 'Un but reste sans buteur attribué.'
                          : '$unattributed buts restent sans buteur attribué.',
                    ),
                  ],
                  const SizedBox(height: 10),
                  const Text(
                    'Les buts, passes décisives, présences et clean sheets '
                    'sont recalculés à partir de ce compte rendu.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(report.isCorrection ? 'Corriger' : 'Valider'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    setState(() => _saving = true);
    try {
      final saved = await ref.read(matchSportReportRepositoryProvider).submit(
            matchId: widget.matchId,
            scoreAsGrinta: _scoreAsGrinta,
            scoreAdverse: _scoreAdverse,
            lineup: lineup,
            goalActions: _goals,
            reason: report.isCorrection
                ? 'Correction du compte rendu'
                : 'Validation du compte rendu',
          );
      if (!mounted) return;
      setState(() => _adopt(saved));
      ref.invalidate(matchDetailsProvider(widget.matchId));
      ref.invalidate(publishedSportMatchResultProvider(widget.matchId));
      _showMessage(
        saved.finalization.version <= 1
            ? 'Compte rendu validé et statistiques synchronisées.'
            : 'Correction enregistrée · version ${saved.finalization.version}.',
      );
      widget.onPublished?.call();
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addPlayer() async {
    final report = _report;
    final lineup = _lineup;
    if (report == null || lineup == null || !_editable || _saving) return;

    final removed = removedEntries(lineup);
    final choice = await showModalBottomSheet<_AddPlayerChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => _AddPlayerSheet(
        removed: removed,
        roster: report.addableRoster,
        guests: report.addableGuests,
      ),
    );
    if (choice == null || !mounted) return;

    if (choice.participantId != null) {
      _updateLineup(restoreEntryToSquad(lineup, choice.participantId!));
      return;
    }

    setState(() => _saving = true);
    try {
      final refreshed =
          await ref.read(matchSportReportRepositoryProvider).attachPlayer(
                matchId: widget.matchId,
                seasonPlayerId: choice.seasonPlayerId,
                guestPlayerId: choice.guestPlayerId,
                reason: 'Ajout d’un joueur au compte rendu',
              );
      if (!mounted) return;
      // Le serveur connaît maintenant le joueur : on garde les modifications
      // locales en cours et on ajoute seulement le nouveau venu sur le banc.
      setState(() {
        final known = {
          for (final entry in lineup.entries) entry.participantId,
        };
        final additions = refreshed.lineup.entries
            .where((entry) => !known.contains(entry.participantId))
            .map((entry) => entry.moveTo(MatchCompositionZone.bench))
            .toList();
        _report = refreshed.copyWith(
          lineup: lineup,
          goalActions: _goals,
        );
        _lineup = lineup.copyWith(entries: [...lineup.entries, ...additions]);
      });
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ----------------------------------------------------------------- vue

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: GrintaProgressIndicator());
    if (_error != null && _report == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
    }
    final report = _report;
    final lineup = _lineup;
    if (report == null || lineup == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!report.isEditable)
          const _ReadOnlyNotice()
        else
          const SizedBox.shrink(),
        _ReportScoreHeader(
          opponentName: report.opponentName,
          scoreAsGrinta: _scoreAsGrinta,
          scoreAdverse: _scoreAdverse,
          enabled: _editable && !_saving,
          onAsGrintaChanged: (value) =>
              _changeScore(asGrinta: true, next: value),
          onAdverseChanged: (value) =>
              _changeScore(asGrinta: false, next: value),
        ),
        TabBar(
          controller: _tabs,
          indicatorColor: AppTheme.accent,
          labelColor: AppTheme.accent,
          unselectedLabelColor: AppTheme.textSecondary,
          dividerColor: AppTheme.outline.withValues(alpha: .45),
          labelStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
          tabs: const [
            Tab(height: 42, text: 'Effectif'),
            Tab(height: 42, text: 'Faits du match'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              // Les deux onglets gardent leur état : passer de l'un à l'autre
              // ne perd aucune modification.
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_editable)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : _addPlayer,
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: const Text('Ajouter un joueur'),
                        ),
                      ),
                    MatchSquadEditor(
                      lineup: lineup,
                      editable: _editable && !_saving,
                      onDroppedOnSlot: _dropOnSlot,
                      onMoveToBench: _moveToBench,
                      onRemoveFromSquad: _removeFromSquad,
                      onFormationChanged: _changeFormation,
                      formationBusy: _saving,
                      header: _SquadHint(
                        starters: lineup
                            .entriesFor(MatchCompositionZone.field)
                            .length,
                      ),
                    ),
                  ],
                ),
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: MatchGoalActionsEditor(
                  goalActions: _goals,
                  squad: _squad,
                  opponentName: report.opponentName,
                  editable: _editable && !_saving,
                  onChanged: _updateGoal,
                  onReorder: _reorderGoals,
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: _editable && !_saving ? _submit : null,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: GrintaProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_rounded),
              label: const Text('VALIDER LE COMPTE RENDU'),
            ),
          ),
        ),
      ],
    );
  }
}

class _SquadHint extends StatelessWidget {
  const _SquadHint({required this.starters});

  final int starters;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                starters == 0
                    ? 'Personne n’est encore sur le terrain. Choisis un '
                        'dispositif, puis glisse les joueurs du banc sur le '
                        'terrain.'
                    : 'Terrain = titulaires, banc = remplaçants. Appuie sur un '
                        'joueur du banc pour le retirer du match.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, color: colors.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'La fenêtre de correction est fermée : ce compte rendu ne peut '
              'plus être modifié.',
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportScoreHeader extends StatelessWidget {
  const _ReportScoreHeader({
    required this.opponentName,
    required this.scoreAsGrinta,
    required this.scoreAdverse,
    required this.enabled,
    required this.onAsGrintaChanged,
    required this.onAdverseChanged,
  });

  final String opponentName;
  final int scoreAsGrinta;
  final int scoreAdverse;
  final bool enabled;
  final ValueChanged<int> onAsGrintaChanged;
  final ValueChanged<int> onAdverseChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          children: [
            _ScoreLine(
              name: 'AS Grinta',
              score: scoreAsGrinta,
              enabled: enabled,
              onChanged: onAsGrintaChanged,
            ),
            const SizedBox(height: 6),
            _ScoreLine(
              name: opponentName,
              score: scoreAdverse,
              enabled: enabled,
              onChanged: onAdverseChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreLine extends StatelessWidget {
  const _ScoreLine({
    required this.name,
    required this.score,
    required this.enabled,
    required this.onChanged,
  });

  final String name;
  final int score;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w400),
          ),
        ),
        IconButton.filledTonal(
          onPressed: enabled && score > 0 ? () => onChanged(score - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '$score',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w400),
          ),
        ),
        IconButton.filledTonal(
          onPressed: enabled && score < 30 ? () => onChanged(score + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

class _AddPlayerChoice {
  const _AddPlayerChoice({
    this.participantId,
    this.seasonPlayerId,
    this.guestPlayerId,
  });

  /// Joueur déjà rattaché au match, simplement retiré du compte rendu.
  final String? participantId;
  final String? seasonPlayerId;
  final String? guestPlayerId;
}

class _AddPlayerSheet extends StatelessWidget {
  const _AddPlayerSheet({
    required this.removed,
    required this.roster,
    required this.guests,
  });

  final List<MatchCompositionEntry> removed;
  final List<MatchReportAddablePlayer> roster;
  final List<MatchReportAddablePlayer> guests;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(
            'Ajouter un joueur',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (removed.isNotEmpty) ...[
            const _SheetSection('Retirés du compte rendu'),
            for (final entry in removed)
              ListTile(
                leading: Icon(
                  entry.isGoalkeeper
                      ? Icons.sports_handball_rounded
                      : Icons.person_rounded,
                ),
                title: Text(entry.displayName),
                onTap: () => Navigator.of(context).pop(
                  _AddPlayerChoice(participantId: entry.participantId),
                ),
              ),
          ],
          if (roster.isNotEmpty) ...[
            const _SheetSection('Effectif de la saison'),
            for (final player in roster)
              ListTile(
                leading: Icon(
                  player.isGoalkeeper
                      ? Icons.sports_handball_rounded
                      : Icons.person_rounded,
                ),
                title: Text(player.displayName),
                onTap: () => Navigator.of(context).pop(
                  _AddPlayerChoice(seasonPlayerId: player.seasonPlayerId),
                ),
              ),
          ],
          if (guests.isNotEmpty) ...[
            const _SheetSection('Invités'),
            for (final player in guests)
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: Text(player.displayName),
                onTap: () => Navigator.of(context).pop(
                  _AddPlayerChoice(guestPlayerId: player.guestPlayerId),
                ),
              ),
          ],
          if (removed.isEmpty && roster.isEmpty && guests.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Tout le monde fait déjà partie du compte rendu.',
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

class _SheetSection extends StatelessWidget {
  const _SheetSection(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w400,
              letterSpacing: .6,
            ),
      ),
    );
  }
}
