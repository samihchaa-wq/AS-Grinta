import 'package:as_grinta/core/design_system/components/grinta_card.dart';
import 'package:as_grinta/core/design_system/components/grinta_icon_button.dart';
import 'package:as_grinta/core/design_system/components/grinta_loading.dart';
import 'package:as_grinta/core/design_system/components/grinta_status_message.dart';
import 'package:as_grinta/core/design_system/components/grinta_surface.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_colors.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_iconography.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_radii.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_spacing.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_typography.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/match_form_page.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/matches/presentation/upcoming_match_prediction_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MatchesPage extends ConsumerStatefulWidget {
  const MatchesPage({super.key});

  @override
  ConsumerState<MatchesPage> createState() => _MatchesPageState();
}

class _MatchesPageState extends ConsumerState<MatchesPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(matchesControllerProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchesControllerProvider);
    final isAdmin =
        ref.watch(authControllerProvider).profile?.role == AuthRole.admin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matchs'),
        actions: [
          if (isAdmin)
            Padding(
              padding: const EdgeInsets.only(right: GrintaSpacing.space2),
              child: GrintaIconButton(
                tooltip: 'Créer un match',
                icon: Icons.add,
                isSelected: true,
                onPressed: () => _createMatch(state.selectedSeasonId),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(matchesControllerProvider.notifier).load(
              seasonId: state.selectedSeasonId,
            ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: GrintaSpacing.contentMaxWidth,
            ),
            child: ListView(
              padding: GrintaSpacing.screenInsets,
              children: [
                if (state.seasons.isNotEmpty &&
                    state.selectedSeasonId != null) ...[
                  _SeasonSelector(
                    seasons: state.seasons,
                    selectedSeasonId: state.selectedSeasonId!,
                    onChanged: (value) async {
                      if (value == state.selectedSeasonId) return;
                      await ref
                          .read(matchesControllerProvider.notifier)
                          .load(seasonId: value);
                    },
                  ),
                  const SizedBox(height: GrintaSpacing.sectionGap),
                ],
                if (state.isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: GrintaSpacing.space20),
                    child: GrintaLoadingIndicator(
                      label: 'Chargement des matchs',
                    ),
                  )
                else if (state.error != null)
                  GrintaStatusMessage(
                    title: 'Impossible de charger les matchs',
                    message: state.error!,
                    tone: GrintaStatusTone.danger,
                  )
                else if (state.matches.isEmpty)
                  const GrintaStatusMessage(
                    title: 'Aucun match',
                    message: 'Aucune rencontre n’est prévue pour cette saison.',
                    tone: GrintaStatusTone.info,
                  )
                else ...[
                  _MatchesHeader(count: state.matches.length),
                  const SizedBox(height: GrintaSpacing.contentGap),
                  ...state.matches.map(
                    (match) => Padding(
                      padding: const EdgeInsets.only(
                        bottom: GrintaSpacing.contentGap,
                      ),
                      child: _MatchCard(
                        match: match,
                        canEdit: isAdmin && !match.isFinished,
                        canFinalize: isAdmin,
                        canDelete: isAdmin,
                        onEdit: () => _editMatch(match),
                        onFinalize: () =>
                            context.push('/matches/${match.id}/finalize'),
                        onDelete: () => _deleteMatch(match),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createMatch(String? seasonId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MatchFormPage()),
    );
    if (!mounted) return;
    await ref.read(matchesControllerProvider.notifier).load(seasonId: seasonId);
  }

  Future<void> _editMatch(MatchModel match) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MatchFormPage(match: match)),
    );
    if (!mounted) return;
    final seasonId = ref.read(matchesControllerProvider).selectedSeasonId;
    await ref.read(matchesControllerProvider.notifier).load(seasonId: seasonId);
  }

  Future<void> _deleteMatch(MatchModel match) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Supprimer ce match ?'),
            content: const Text(
              'Le match, ses pronostics et ses statistiques seront '
              'définitivement supprimés.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: const Text('Supprimer'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;
    await ref.read(matchesControllerProvider.notifier).deleteMatch(match.id);
  }
}

class _SeasonSelector extends StatelessWidget {
  const _SeasonSelector({
    required this.seasons,
    required this.selectedSeasonId,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> seasons;
  final String selectedSeasonId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return GrintaCard(
      title: 'Saison',
      subtitle: 'Filtrer les rencontres',
      leading: const Icon(Icons.calendar_month_outlined),
      child: DropdownButtonFormField<String>(
        initialValue: selectedSeasonId,
        decoration: const InputDecoration(labelText: 'Saison sélectionnée'),
        items: seasons
            .map(
              (season) => DropdownMenuItem(
                value: season['id'].toString(),
                child: Text(season['name'].toString()),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

class _MatchesHeader extends StatelessWidget {
  const _MatchesHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Calendrier',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        Text(
          '$count match${count > 1 ? 's' : ''}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.canDelete,
    required this.canEdit,
    required this.canFinalize,
    required this.onEdit,
    required this.onFinalize,
    required this.onDelete,
  });

  final MatchModel match;
  final bool canDelete;
  final bool canEdit;
  final bool canFinalize;
  final VoidCallback onEdit;
  final VoidCallback onFinalize;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isFinished = match.isFinished;
    final opponent = match.opponentName ?? 'Adversaire';
    final homeName = match.isHome ? 'AS Grinta' : opponent;
    final awayName = match.isHome ? opponent : 'AS Grinta';
    final homeScore = match.isHome ? match.grintaScore : match.opponentScore;
    final awayScore = match.isHome ? match.opponentScore : match.grintaScore;

    return GrintaCard(
      level:
          isFinished ? GrintaSurfaceLevel.raised : GrintaSurfaceLevel.emphasis,
      onTap: () {
        if (isFinished) {
          context.push('/matches/${match.id}');
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => UpcomingMatchPredictionPage(matchId: match.id),
            ),
          );
        }
      },
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MatchStatus(isFinished: isFinished),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.schedule_outlined,
                    size: GrintaIconography.inline,
                    color: GrintaColors.contentTertiary,
                  ),
                  const SizedBox(width: GrintaSpacing.iconGap),
                  Text(
                    _formatKickoff(match.kickoffAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: GrintaSpacing.sectionGap),
          Row(
            children: [
              Expanded(
                child: _CompactTeam(
                  name: homeName,
                  isGrinta: homeName == 'AS Grinta',
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: GrintaSpacing.space3,
                ),
                child: isFinished
                    ? Text(
                        '${homeScore ?? 0}–${awayScore ?? 0}',
                        style: GrintaTypography.score.copyWith(fontSize: 32),
                      )
                    : Text(
                        'VS',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: GrintaColors.contentTertiary,
                                ),
                      ),
              ),
              Expanded(
                child: _CompactTeam(
                  name: awayName,
                  isGrinta: awayName == 'AS Grinta',
                ),
              ),
            ],
          ),
          if (canEdit || canFinalize || canDelete) ...[
            const SizedBox(height: GrintaSpacing.sectionGap),
            const Divider(),
            const SizedBox(height: GrintaSpacing.space2),
            Align(
              alignment: Alignment.centerRight,
              child: PopupMenuButton<_MatchAction>(
                tooltip: 'Actions du match',
                icon: const Icon(Icons.more_horiz),
                onSelected: (action) {
                  switch (action) {
                    case _MatchAction.edit:
                      onEdit();
                    case _MatchAction.finalize:
                      onFinalize();
                    case _MatchAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (context) => [
                  if (canEdit)
                    const PopupMenuItem(
                      value: _MatchAction.edit,
                      child: _MenuEntry(
                        icon: Icons.edit_outlined,
                        label: 'Modifier le match',
                      ),
                    ),
                  if (canFinalize)
                    PopupMenuItem(
                      value: _MatchAction.finalize,
                      child: _MenuEntry(
                        icon: Icons.fact_check_outlined,
                        label: isFinished
                            ? 'Modifier les statistiques'
                            : 'Saisir les statistiques',
                      ),
                    ),
                  if (canDelete)
                    const PopupMenuItem(
                      value: _MatchAction.delete,
                      child: _MenuEntry(
                        icon: Icons.delete_outline,
                        label: 'Supprimer le match',
                        destructive: true,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatKickoff(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)} • '
        '${two(value.hour)}h${two(value.minute)}';
  }
}

enum _MatchAction { edit, finalize, delete }

class _MatchStatus extends StatelessWidget {
  const _MatchStatus({required this.isFinished});

  final bool isFinished;

  @override
  Widget build(BuildContext context) {
    final color =
        isFinished ? GrintaColors.statusSuccess : GrintaColors.statusWarning;
    final background = isFinished
        ? GrintaColors.statusSuccessSoft
        : GrintaColors.statusWarningSoft;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GrintaSpacing.space3,
        vertical: GrintaSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: GrintaRadii.badgeRadius,
      ),
      child: Text(
        isFinished ? 'TERMINÉ' : 'À VENIR',
        style: GrintaTypography.eyebrow.copyWith(color: color),
      ),
    );
  }
}

class _CompactTeam extends StatelessWidget {
  const _CompactTeam({required this.name, required this.isGrinta});

  final String name;
  final bool isGrinta;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isGrinta
                ? GrintaColors.actionPrimary
                : GrintaColors.surfaceElevated,
            shape: BoxShape.circle,
            border: Border.all(color: GrintaColors.borderDefault),
          ),
          child: Icon(
            isGrinta ? Icons.shield_outlined : Icons.sports_soccer_outlined,
            size: GrintaIconography.control,
            color: isGrinta
                ? GrintaColors.actionPrimaryContent
                : GrintaColors.contentSecondary,
          ),
        ),
        const SizedBox(height: GrintaSpacing.space2),
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ],
    );
  }
}

class _MenuEntry extends StatelessWidget {
  const _MenuEntry({
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurface;

    return Row(
      children: [
        Icon(icon, size: GrintaIconography.inline, color: color),
        const SizedBox(width: GrintaSpacing.inlineGap),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}
