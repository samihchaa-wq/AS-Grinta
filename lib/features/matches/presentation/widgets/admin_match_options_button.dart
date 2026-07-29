import 'package:as_grinta/features/home/data/home_repository.dart';
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
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MatchFormPage(match: match)),
    );
    if (!context.mounted) return;
    ref
      ..invalidate(homeDashboardProvider)
      ..invalidate(matchDetailsProvider(match.id));
    await ref.read(matchesControllerProvider.notifier).load(allSeasons: true);
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
    ref
      ..invalidate(homeDashboardProvider)
      ..invalidate(matchDetailsProvider(match.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          case 'delete':
            await _delete(context, ref);
            return;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'edit',
          child: ListTile(
            leading: Icon(Icons.settings_outlined),
            title: Text('Modifier'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'stats',
          child: ListTile(
            leading: Icon(Icons.query_stats_outlined),
            title: Text('Stats'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('Supprimer'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
