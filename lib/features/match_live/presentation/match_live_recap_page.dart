import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/match_live/data/match_live_repository.dart';
import 'package:as_grinta/features/match_live/domain/match_live_state_bundle.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/live_substitution_line.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/sports_management/data/sport_match_finalization_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/sport_match_finalization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Grand récapitulatif entièrement modifiable après "Fin du match" : score,
/// buteurs, remplacements (lecture seule, déjà horodatés en direct) et
/// présences (corrigibles). "Exporter vers compte rendu ?" publie via le
/// pipeline de finalisation existant, inchangé.
class MatchLiveRecapPage extends ConsumerStatefulWidget {
  const MatchLiveRecapPage({
    super.key,
    required this.matchId,
    required this.bundle,
  });

  final String matchId;
  final MatchLiveStateBundle bundle;

  @override
  ConsumerState<MatchLiveRecapPage> createState() => _MatchLiveRecapPageState();
}

class _MatchLiveRecapPageState extends ConsumerState<MatchLiveRecapPage> {
  SportMatchFinalization? _finalization;
  bool _loading = true;
  bool _saving = false;
  String? _error;

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
      final value = await ref
          .read(sportMatchFinalizationRepositoryProvider)
          .fetchAdminContext(widget.matchId);
      if (!mounted) return;
      setState(() => _finalization = _seedFromLiveTracking(value));
    } catch (error) {
      if (mounted) setState(() => _error = humanizeError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Préremplit présence/rôle depuis la composition suivie en direct, et les
  /// buts depuis les événements "but AS Grinta" horodatés.
  SportMatchFinalization _seedFromLiveTracking(SportMatchFinalization base) {
    final lineup = widget.bundle.lineup;
    final goalsByParticipant = <String, int>{};
    for (final event in widget.bundle.ownGoals) {
      final id = event.scorerParticipantId;
      if (id == null) continue;
      goalsByParticipant[id] = (goalsByParticipant[id] ?? 0) + 1;
    }
    return base.copyWith(
      scoreAsGrinta: widget.bundle.session.scoreAsGrinta,
      scoreAdverse: widget.bundle.session.scoreAdverse,
      participants: [
        for (final participant in base.participants)
          _seedParticipant(participant, lineup, goalsByParticipant),
      ],
    );
  }

  SportFinalParticipant _seedParticipant(
    SportFinalParticipant participant,
    MatchComposition? lineup,
    Map<String, int> goalsByParticipant,
  ) {
    final liveEntry = lineup?.entries
        .where(
          (entry) => entry.participantId == participant.participantId,
        )
        .firstOrNull;
    if (liveEntry == null) return participant;
    final present = liveEntry.zone == MatchCompositionZone.field ||
        liveEntry.zone == MatchCompositionZone.bench;
    return participant.copyWith(
      present: present,
      selectionStatus: switch (liveEntry.zone) {
        MatchCompositionZone.field => SportFinalSelectionStatus.starter,
        MatchCompositionZone.bench => SportFinalSelectionStatus.substitute,
        _ => SportFinalSelectionStatus.notSelected,
      },
      goals: present ? (goalsByParticipant[participant.participantId] ?? 0) : 0,
    );
  }

  void _updateParticipant(
    SportFinalParticipant participant,
    SportFinalParticipant next,
  ) {
    final current = _finalization;
    if (current == null || _saving) return;
    setState(() {
      _finalization = current.copyWith(
        participants: [
          for (final item in current.participants)
            if (item.participantId == participant.participantId) next else item,
        ],
      );
    });
  }

  void _setPresent(SportFinalParticipant participant, bool present) {
    _updateParticipant(
      participant,
      participant.copyWith(
        present: present,
        selectionStatus: present
            ? participant.selectionStatus
            : SportFinalSelectionStatus.notSelected,
        goals: present ? participant.goals : 0,
        cleanSheet: present ? participant.cleanSheet : false,
      ),
    );
  }

  void _setCleanSheet(SportFinalParticipant participant, bool enabled) {
    final current = _finalization;
    if (current == null || !participant.isGoalkeeper || !participant.present) {
      return;
    }
    setState(() {
      _finalization = current.copyWith(
        participants: [
          for (final item in current.participants)
            if (item.participantId == participant.participantId)
              item.copyWith(cleanSheet: enabled)
            else if (enabled && item.cleanSheet)
              item.copyWith(cleanSheet: false)
            else
              item,
        ],
      );
    });
  }

  String? _validate(SportMatchFinalization value) {
    if (value.presentCount == 0) {
      return 'Sélectionne au moins une personne réellement présente.';
    }
    if (value.starterCount > 11) {
      return 'Il ne peut pas y avoir plus de 11 titulaires réels.';
    }
    if (value.attributedGoals > value.scoreAsGrinta) {
      return 'Les buts attribués dépassent le score d’AS Grinta.';
    }
    if (value.scoreAdverse > 0 &&
        value.participants.any((participant) => participant.cleanSheet)) {
      return 'Un clean sheet est impossible lorsque l’adversaire a marqué.';
    }
    return null;
  }

  Future<void> _submit() async {
    final value = _finalization;
    if (value == null || _saving) return;
    final validationError = _validate(value);
    if (validationError != null) {
      _showMessage(validationError);
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Exporter vers compte rendu ?'),
            content: Text(
              '${value.presentCount} présents · ${value.starterCount} '
              'titulaires · ${value.attributedGoals} buts attribués.\n\n'
              'Les statistiques seront publiées dans la fiche du match et '
              'le vote Homme du Match s’ouvrira pour les joueurs.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Non'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Oui'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    setState(() => _saving = true);
    try {
      await ref.read(matchLiveRepositoryProvider).publishRecap(
            matchId: widget.matchId,
            scoreAsGrinta: value.scoreAsGrinta,
            scoreAdverse: value.scoreAdverse,
            participants: value.participants,
            reason: 'Export depuis le Tableau Blanc',
          );
      ref
        ..invalidate(matchDetailsProvider(widget.matchId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Match publié dans le compte rendu.')),
      );
      context.go('/matches/${widget.matchId}');
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: GrintaProgressIndicator());
    if (_error != null && _finalization == null) {
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
    final value = _finalization;
    if (value == null) return const SizedBox.shrink();

    // Cette liste est déjà imbriquée dans le scroll de la page qui l'affiche.
    // Sans shrinkWrap + NeverScrollableScrollPhysics, les deux listes se
    // disputent les gestes tactiles : scroll bloqué avant le bouton
    // « Valider ».
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        Text(
          'Récapitulatif du match',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Tout est modifiable avant l’export.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Score final',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                _ScoreLine(
                  name: 'AS Grinta',
                  score: value.scoreAsGrinta,
                  enabled: !_saving,
                  onChanged: (score) => setState(
                    () => _finalization = value.copyWith(scoreAsGrinta: score),
                  ),
                ),
                const SizedBox(height: 8),
                _ScoreLine(
                  name: value.opponentName,
                  score: value.scoreAdverse,
                  enabled: !_saving,
                  onChanged: (score) {
                    setState(() {
                      var participants = value.participants;
                      if (score > 0) {
                        participants = [
                          for (final participant in participants)
                            participant.cleanSheet
                                ? participant.copyWith(cleanSheet: false)
                                : participant,
                        ];
                      }
                      _finalization = value.copyWith(
                        scoreAdverse: score,
                        participants: participants,
                      );
                    });
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (widget.bundle.substitutions.isNotEmpty) ...[
          Text('Remplacements', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (final event in widget.bundle.substitutions)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.swap_horiz_rounded),
                    title: LiveSubstitutionLine(
                      playerInName: event.playerInName ?? '?',
                      playerOutName: event.playerOutName ?? '?',
                    ),
                    trailing: Text("${event.minute}'"),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text('Présences', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final participant in value.participants)
          _RecapParticipantCard(
            participant: participant,
            opponentScore: value.scoreAdverse,
            saving: _saving,
            onPresentChanged: (present) => _setPresent(participant, present),
            onGoalsChanged: (goals) => _updateParticipant(
              participant,
              participant.copyWith(goals: goals),
            ),
            onCleanSheetChanged: (enabled) =>
                _setCleanSheet(participant, enabled),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: GrintaProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.ios_share_rounded),
          label: const Text('Valider'),
        ),
      ],
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
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
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
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
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

class _RecapParticipantCard extends StatelessWidget {
  const _RecapParticipantCard({
    required this.participant,
    required this.opponentScore,
    required this.saving,
    required this.onPresentChanged,
    required this.onGoalsChanged,
    required this.onCleanSheetChanged,
  });

  final SportFinalParticipant participant;
  final int opponentScore;
  final bool saving;
  final ValueChanged<bool> onPresentChanged;
  final ValueChanged<int> onGoalsChanged;
  final ValueChanged<bool> onCleanSheetChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: participant.present,
              onChanged: saving ? null : onPresentChanged,
              secondary: CircleAvatar(
                child: Text(participant.isGoalkeeper ? '🧤' : '⚽'),
              ),
              title: Text(
                participant.displayName.trim(),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                participant.isGuest ? 'Invité' : 'Effectif',
              ),
            ),
            if (participant.present) ...[
              const Divider(),
              Row(
                children: [
                  const Expanded(child: Text('Buts inscrits')),
                  IconButton.filledTonal(
                    onPressed: saving || participant.goals == 0
                        ? null
                        : () => onGoalsChanged(participant.goals - 1),
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(
                    width: 38,
                    child: Text(
                      '${participant.goals}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: saving || participant.goals >= 30
                        ? null
                        : () => onGoalsChanged(participant.goals + 1),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              if (participant.isGoalkeeper)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: participant.cleanSheet,
                  onChanged: saving || opponentScore > 0
                      ? null
                      : (value) => onCleanSheetChanged(value == true),
                  title: const Text('Clean sheet'),
                  subtitle: opponentScore > 0
                      ? const Text('Impossible : l’adversaire a marqué.')
                      : const Text('Un seul gardien peut être crédité.'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
