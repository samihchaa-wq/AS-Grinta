import 'package:as_grinta/core/utils/match_window.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/match_form_page.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AdminMatchOptionsButton extends ConsumerWidget {
  const AdminMatchOptionsButton({required this.match, super.key});

  final MatchModel match;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => MatchFormPage(match: match)));
    if (!context.mounted) return;
    ref.invalidate(matchDetailsProvider(match.id));
    await ref.read(matchesControllerProvider.notifier).load(allSeasons: true);
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Annuler ce match ?'),
            content: const Text(
              'Le match sera marqué comme annulé. Il reste visible dans le '
              'calendrier pour informer les joueurs, mais ne sera plus '
              'ouvrable.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Retour'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Annuler le match'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    await ref.read(matchesControllerProvider.notifier).cancelMatch(match.id);
    ref.invalidate(matchDetailsProvider(match.id));
  }

  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Terminer ce match ?'),
            content: const Text(
              'Le match entre nous sera marqué comme terminé et sortira des '
              'matchs en cours. Cette action ne peut pas être annulée depuis '
              'l’application.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Retour'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Terminer'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    await ref
        .read(matchesControllerProvider.notifier)
        .finishInternalMatch(match.id);
    ref.invalidate(matchDetailsProvider(match.id));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Supprimer ce match ?'),
            content: const Text(
              'Le match, ses pronostics, ses buteurs et ses statistiques seront '
              'définitivement supprimés.',
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
    if (!confirmed || !context.mounted) return;
    await ref.read(matchesControllerProvider.notifier).deleteMatch(match.id);
    ref.invalidate(matchDetailsProvider(match.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = match.phase();
    final editLocked =
        isMatchAdminEditLocked(match.kickoffAt) || match.isFinished;
    final canEditIdentity = !editLocked && !match.isCancelled;
    final canCancel = !editLocked && !match.isCancelled;
    final canDelete = !editLocked;
    final canEnterStats = !match.isInternal &&
        !match.isArchived &&
        (phase == MatchDisplayPhase.awaitingValidation ||
            (phase == MatchDisplayPhase.past && match.status == 'termine'));
    final canFinishInternal = match.isInternal &&
        !match.isFinished &&
        !match.isCancelled &&
        !DateTime.now().isBefore(match.kickoffAt) &&
        (phase == MatchDisplayPhase.live ||
            phase == MatchDisplayPhase.awaitingValidation);

    return PopupMenuButton<String>(
      tooltip: 'Options du match',
      icon: const Icon(Icons.edit_outlined),
      onSelected: (value) async {
        switch (value) {
          case 'edit':
            await _edit(context, ref);
            return;
          case 'stats':
            if (context.mounted) {
              context.push('/matches/${match.id}/finalize');
            }
            return;
          case 'finish':
            await _finish(context, ref);
            return;
          case 'cancel':
            await _cancel(context, ref);
            return;
          case 'delete':
            await _delete(context, ref);
            return;
        }
      },
      itemBuilder: (context) => [
        if (canEditIdentity)
          const PopupMenuItem(
            value: 'edit',
            child: ListTile(
              leading: Icon(Icons.settings_outlined),
              title: Text('Modifier'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canEnterStats)
          PopupMenuItem(
            value: 'stats',
            child: ListTile(
              leading: const Icon(Icons.query_stats_outlined),
              title: Text(
                phase == MatchDisplayPhase.past
                    ? 'Corriger le compte rendu'
                    : 'Saisir les stats',
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canFinishInternal)
          const PopupMenuItem(
            value: 'finish',
            child: ListTile(
              leading: Icon(Icons.check_circle_outline),
              title: Text('Terminer'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canCancel)
          const PopupMenuItem(
            value: 'cancel',
            child: ListTile(
              leading: Icon(Icons.block_outlined),
              title: Text('Annuler'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canDelete)
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('Supprimer'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (!canEditIdentity &&
            !canEnterStats &&
            !canFinishInternal &&
            !canCancel &&
            !canDelete)
          const PopupMenuItem(
            enabled: false,
            child: ListTile(
              leading: Icon(Icons.lock_outline_rounded),
              title: Text('Match verrouillé'),
              subtitle: Text(
                'Utilise le Live ou la correction du compte rendu.',
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }
}
