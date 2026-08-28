import 'package:as_grinta/features/match_live/presentation/widgets/match_live_scorer_picker_dialog.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/match_goal_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Onglet « Faits du match » : la chronologie des buts des deux camps.
///
/// On y corrige la minute, le buteur, le passeur et les contre-son-camp. Les
/// remplacements n'y figurent pas : ils appartiennent au suivi en direct, pas
/// au compte rendu sportif.
class MatchGoalActionsEditor extends StatelessWidget {
  const MatchGoalActionsEditor({
    super.key,
    required this.goalActions,
    required this.squad,
    required this.opponentName,
    required this.editable,
    required this.onChanged,
    required this.onReorder,
  });

  final List<MatchGoalAction> goalActions;

  /// Joueurs de l'effectif du compte rendu : les seuls qu'on peut désigner.
  final List<MatchCompositionEntry> squad;
  final String opponentName;
  final bool editable;
  final void Function(MatchGoalAction updated) onChanged;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    if (goalActions.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.sports_soccer_rounded, size: 32),
              const SizedBox(height: 10),
              Text(
                'Aucun but sur ce match.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              const Text(
                'Change le score dans l’en-tête pour ajouter des buts à '
                'compléter.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (editable)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Row(
              children: [
                const Icon(Icons.drag_indicator_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Appuie longuement sur un but pour le remonter ou le '
                    'descendre dans la chronologie.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: editable,
          itemCount: goalActions.length,
          onReorderItem: onReorder,
          itemBuilder: (context, index) {
            final goal = goalActions[index];
            return _GoalActionCard(
              key: ValueKey(goal.localKey),
              goal: goal,
              squad: squad,
              opponentName: opponentName,
              editable: editable,
              onChanged: onChanged,
            );
          },
        ),
      ],
    );
  }
}

class _GoalActionCard extends StatelessWidget {
  const _GoalActionCard({
    super.key,
    required this.goal,
    required this.squad,
    required this.opponentName,
    required this.editable,
    required this.onChanged,
  });

  final MatchGoalAction goal;
  final List<MatchCompositionEntry> squad;
  final String opponentName;
  final bool editable;
  final void Function(MatchGoalAction updated) onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final incomplete = goal.hasUnknownScorer;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: incomplete ? colors.surfaceContainerHighest : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _MinuteField(
                  minute: goal.minute,
                  editable: editable,
                  onChanged: (minute) => onChanged(goal.withMinute(minute)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    goal.isAsGrinta ? 'AS Grinta' : opponentName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: goal.isAsGrinta ? colors.primary : colors.error,
                    ),
                  ),
                ),
                Icon(
                  Icons.sports_soccer_rounded,
                  size: 20,
                  color: goal.isAsGrinta ? colors.primary : colors.error,
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (goal.isAsGrinta)
              ..._buildAsGrintaRows(context)
            else
              _buildOpponentRow(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAsGrintaRows(BuildContext context) {
    return [
      _AttributionTile(
        icon: Icons.sports_soccer_rounded,
        label: 'Buteur',
        value: goal.isOwnGoal
            ? 'CSC adverse'
            : (goal.scorerName ?? 'Non attribué'),
        muted: goal.hasUnknownScorer,
        enabled: editable,
        onTap: () => _pickScorer(context),
      ),
      if (goal.canCarryAssist)
        _AttributionTile(
          icon: Icons.handshake_rounded,
          label: 'Passe décisive',
          value: switch (goal.assistKind) {
            MatchGoalAssistKind.player => goal.assistName ?? 'Non attribué',
            MatchGoalAssistKind.none => 'Aucune passe décisive',
            MatchGoalAssistKind.unknown => 'Non attribuée',
          },
          muted: goal.assistKind != MatchGoalAssistKind.player,
          // Sans buteur, il n'y a pas de passe décisive à rattacher.
          enabled: editable && goal.scorerParticipantId != null,
          onTap: () => _pickAssist(context),
        ),
    ];
  }

  Widget _buildOpponentRow(BuildContext context) {
    return _AttributionTile(
      icon: Icons.flag_rounded,
      label: 'Origine du but',
      value: goal.isOwnGoal ? 'CSC AS Grinta' : 'But de $opponentName',
      muted: false,
      enabled: editable,
      onTap: () => _pickOpponentOrigin(context),
    );
  }

  Future<void> _pickScorer(BuildContext context) async {
    final choice = await pickMatchLiveScorer(
      context,
      candidates: squad,
      title: 'Qui a marqué ?',
      extraChoiceLabel: 'CSC adverse',
      extraChoiceIcon: Icons.shield_moon_outlined,
      clearChoiceLabel: 'Buteur inconnu',
      clearChoiceIcon: Icons.help_outline,
    );
    if (choice == null) return;
    if (choice == kMatchLiveExtraChoiceId) {
      onChanged(goal.withOwnGoal());
      return;
    }
    if (choice == kMatchLiveClearChoiceId) {
      onChanged(goal.withUnknownScorer());
      return;
    }
    final entry = squad
        .where((candidate) => candidate.participantId == choice)
        .firstOrNull;
    if (entry != null) onChanged(goal.withScorer(choice, entry.displayName));
  }

  Future<void> _pickAssist(BuildContext context) async {
    // Personne ne se fait de passe à soi-même : le buteur sort de la liste.
    final candidates = squad
        .where((entry) => entry.participantId != goal.scorerParticipantId)
        .toList();
    final choice = await pickMatchLiveScorer(
      context,
      candidates: candidates,
      title: 'Qui a fait la passe ?',
      icon: Icons.handshake_rounded,
      extraChoiceLabel: 'Aucune passe décisive',
      extraChoiceIcon: Icons.block_rounded,
      clearChoiceLabel: 'Passeur inconnu',
      clearChoiceIcon: Icons.help_outline,
    );
    if (choice == null) return;
    if (choice == kMatchLiveExtraChoiceId) {
      onChanged(goal.withNoAssist());
      return;
    }
    if (choice == kMatchLiveClearChoiceId) {
      onChanged(goal.withUnknownAssist());
      return;
    }
    final entry = candidates
        .where((candidate) => candidate.participantId == choice)
        .firstOrNull;
    if (entry != null) onChanged(goal.withAssist(choice, entry.displayName));
  }

  Future<void> _pickOpponentOrigin(BuildContext context) async {
    final ownGoal = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_rounded),
              title: Text('But de $opponentName'),
              onTap: () => Navigator.of(sheetContext).pop(false),
            ),
            ListTile(
              leading: const Icon(Icons.shield_moon_outlined),
              title: const Text('CSC AS Grinta'),
              subtitle: const Text(
                'Un de nos joueurs a marqué contre son camp.',
              ),
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
          ],
        ),
      ),
    );
    if (ownGoal == null) return;
    onChanged(ownGoal ? goal.withOwnGoal() : goal.withoutOwnGoal());
  }
}

class _MinuteField extends StatefulWidget {
  const _MinuteField({
    required this.minute,
    required this.editable,
    required this.onChanged,
  });

  final int? minute;
  final bool editable;
  final ValueChanged<int?> onChanged;

  @override
  State<_MinuteField> createState() => _MinuteFieldState();
}

class _MinuteFieldState extends State<_MinuteField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.minute?.toString() ?? '');

  @override
  void didUpdateWidget(covariant _MinuteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final expected = widget.minute?.toString() ?? '';
    if (_controller.text != expected && !_hasFocus) {
      _controller.text = expected;
    }
  }

  bool _hasFocus = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      child: Focus(
        onFocusChange: (value) => _hasFocus = value,
        child: TextField(
          controller: _controller,
          enabled: widget.editable,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Min.',
            hintText: '?',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            final text = value.trim();
            if (text.isEmpty) {
              widget.onChanged(null);
              return;
            }
            final minute = int.tryParse(text);
            // Une minute hors de 0–90 n'est jamais enregistrée : le champ la
            // refuse au lieu de laisser la validation échouer plus tard.
            if (minute == null || minute < 0 || minute > kMatchGoalMaxMinute) {
              return;
            }
            widget.onChanged(minute);
          },
        ),
      ),
    );
  }
}

class _AttributionTile extends StatelessWidget {
  const _AttributionTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.muted,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool muted;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20),
      title: Text(label, style: Theme.of(context).textTheme.bodySmall),
      subtitle: Text(
        value,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: muted ? colors.outline : null,
        ),
      ),
      trailing: enabled ? const Icon(Icons.edit_rounded, size: 18) : null,
      onTap: enabled ? onTap : null,
    );
  }
}
