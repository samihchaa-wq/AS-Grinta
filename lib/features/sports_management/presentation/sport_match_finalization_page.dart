import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/home/data/home_repository.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/sports_management/data/sport_match_finalization_repository.dart';
import 'package:as_grinta/features/sports_management/domain/sport_match_finalization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SportMatchFinalizationPage extends ConsumerStatefulWidget {
  const SportMatchFinalizationPage({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<SportMatchFinalizationPage> createState() =>
      _SportMatchFinalizationPageState();
}

class _SportMatchFinalizationPageState
    extends ConsumerState<SportMatchFinalizationPage> {
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
      setState(() => _finalization = value);
    } catch (error) {
      if (mounted) setState(() => _error = humanizeError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    final nextRole = present
        ? _defaultRole(participant)
        : SportFinalSelectionStatus.notSelected;
    _updateParticipant(
      participant,
      participant.copyWith(
        present: present,
        selectionStatus: nextRole,
        goals: present ? participant.goals : 0,
        cleanSheet: present ? participant.cleanSheet : false,
      ),
    );
  }

  SportFinalSelectionStatus _defaultRole(SportFinalParticipant participant) {
    if (participant.present) return participant.selectionStatus;
    return switch (participant.plannedZone) {
      'field' => SportFinalSelectionStatus.starter,
      'bench' => SportFinalSelectionStatus.substitute,
      _ => SportFinalSelectionStatus.notSelected,
    };
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
    if (DateTime.now().isBefore(value.kickoffAt)) {
      return 'Le match ne peut pas être validé avant le coup d’envoi.';
    }
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

    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              value.isValidated
                  ? 'Corriger les statistiques du match ?'
                  : 'Valider le match et les statistiques ?',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${value.presentCount} présents · ${value.starterCount} titulaires · '
                    '${value.substituteCount} remplaçants · ${value.attributedGoals} buts attribués.',
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Les joueurs permanents alimenteront immédiatement les statistiques, '
                    'les badges et les classements. Les invités resteront liés au résultat.',
                  ),
                  if (value.isValidated) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: reasonController,
                      maxLength: 500,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Motif de la correction',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton.icon(
                onPressed: () {
                  if (value.isValidated &&
                      reasonController.text.trim().isEmpty) {
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                icon: const Icon(Icons.verified_outlined),
                label: Text(value.isValidated ? 'Corriger' : 'Valider'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) {
      reasonController.dispose();
      return;
    }

    setState(() => _saving = true);
    try {
      final saved =
          await ref.read(sportMatchFinalizationRepositoryProvider).finalize(
                finalization: value,
                reason: value.isValidated
                    ? reasonController.text.trim()
                    : 'Validation sportive depuis Flutter',
              );
      if (!mounted) return;
      setState(() => _finalization = saved);
      ref.invalidate(matchDetailsProvider(widget.matchId));
      ref.invalidate(homeDashboardProvider);
      ref.invalidate(publishedSportMatchResultProvider(widget.matchId));
      _showMessage(
        saved.version == 1
            ? 'Match validé et statistiques synchronisées.'
            : 'Correction enregistrée · version ${saved.version}.',
      );
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
    } finally {
      reasonController.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GrintaAppBar(
        title: const Text('Validation du match'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loading || _saving ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _SummaryCard(
          value: value,
          saving: _saving,
          onScoreAsGrintaChanged: (score) => setState(
            () => _finalization = value.copyWith(scoreAsGrinta: score),
          ),
          onScoreAdverseChanged: (score) {
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
        const SizedBox(height: 16),
        Text(
          'Présence réelle et statistiques',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'La composition publiée sert uniquement de préremplissage. Corrige ici '
          'ce qui s’est réellement passé.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final participant in value.participants)
          _ParticipantCard(
            participant: participant,
            opponentScore: value.scoreAdverse,
            saving: _saving,
            onPresentChanged: (present) => _setPresent(participant, present),
            onRoleChanged: (role) => _updateParticipant(
              participant,
              participant.copyWith(selectionStatus: role),
            ),
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
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.verified_outlined),
          label: Text(
            value.isValidated
                ? 'Corriger le match et recalculer les statistiques'
                : 'Valider le match et alimenter les statistiques',
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Après validation, cette liste servira de base au scrutin Homme du match.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.value,
    required this.saving,
    required this.onScoreAsGrintaChanged,
    required this.onScoreAdverseChanged,
  });

  final SportMatchFinalization value;
  final bool saving;
  final ValueChanged<int> onScoreAsGrintaChanged;
  final ValueChanged<int> onScoreAdverseChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    value.opponentName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                Chip(
                  label: Text(
                    value.isValidated
                        ? 'Version ${value.version}'
                        : 'À valider',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _ScoreStepper(
                    label: 'AS Grinta',
                    value: value.scoreAsGrinta,
                    enabled: !saving,
                    onChanged: onScoreAsGrintaChanged,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('–', style: TextStyle(fontSize: 26)),
                ),
                Expanded(
                  child: _ScoreStepper(
                    label: 'Adversaire',
                    value: value.scoreAdverse,
                    enabled: !saving,
                    onChanged: onScoreAdverseChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('${value.presentCount} présents')),
                Chip(label: Text('${value.starterCount}/11 titulaires')),
                Chip(label: Text('${value.substituteCount} remplaçants')),
                if (value.guestPresentCount > 0)
                  Chip(label: Text('${value.guestPresentCount} invités')),
                Chip(
                  label: Text(
                    '${value.attributedGoals}/${value.scoreAsGrinta} buts attribués',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreStepper extends StatelessWidget {
  const _ScoreStepper({
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
    return Column(
      children: [
        Text(label, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              onPressed:
                  enabled && value > 0 ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 42,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton.filledTonal(
              onPressed:
                  enabled && value < 30 ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }
}

class _ParticipantCard extends StatelessWidget {
  const _ParticipantCard({
    required this.participant,
    required this.opponentScore,
    required this.saving,
    required this.onPresentChanged,
    required this.onRoleChanged,
    required this.onGoalsChanged,
    required this.onCleanSheetChanged,
  });

  final SportFinalParticipant participant;
  final int opponentScore;
  final bool saving;
  final ValueChanged<bool> onPresentChanged;
  final ValueChanged<SportFinalSelectionStatus> onRoleChanged;
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
                participant.displayName,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${participant.isGuest ? 'Invité' : 'Effectif'} · '
                'prévu ${_plannedLabel(participant.plannedZone)}',
              ),
            ),
            if (participant.present) ...[
              const Divider(),
              DropdownButtonFormField<SportFinalSelectionStatus>(
                initialValue: participant.selectionStatus,
                decoration: const InputDecoration(
                  labelText: 'Rôle réel',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final role in SportFinalSelectionStatus.values)
                    DropdownMenuItem(value: role, child: Text(role.label)),
                ],
                onChanged: saving
                    ? null
                    : (value) {
                        if (value != null) onRoleChanged(value);
                      },
              ),
              const SizedBox(height: 10),
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

String _plannedLabel(String zone) {
  return switch (zone) {
    'field' => 'titulaire',
    'bench' => 'sur le banc',
    'not_selected' => 'non convoqué',
    _ => 'sans rôle',
  };
}
