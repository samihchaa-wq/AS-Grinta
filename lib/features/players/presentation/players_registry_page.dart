import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/features/players/data/roster_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Effectif de la saison : la liste des joueurs (prénom, nom, gardien) sur qui
/// les pronostiqueurs parient. Indépendant des comptes.
class PlayersRegistryPage extends ConsumerWidget {
  const PlayersRegistryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seasonAsync = ref.watch(openSeasonIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Effectif')),
      body: seasonAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(humanizeError(error))),
        data: (seasonId) {
          if (seasonId == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aucune saison ouverte. Crée une saison dans '
                  'Administration pour définir ton effectif.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _RosterList(seasonId: seasonId);
        },
      ),
      floatingActionButton: seasonAsync.valueOrNull == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showPlayerDialog(context, ref,
                  seasonId: seasonAsync.value!),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Ajouter'),
            ),
    );
  }
}

class _RosterList extends ConsumerWidget {
  const _RosterList({required this.seasonId});

  final String seasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rosterAsync = ref.watch(rosterProvider(seasonId));

    return rosterAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(humanizeError(error))),
      data: (players) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(rosterProvider(seasonId));
          await ref.read(rosterProvider(seasonId).future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Les joueurs sur qui on parie'),
                subtitle: Text(
                  'Ajoute ici les joueurs de l’équipe (prénom, nom, gardien). '
                  'Les buts, clean sheets et pronostics de saison portent sur '
                  'eux. Aucun compte requis.',
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (players.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('Aucun joueur dans l’effectif.'),
                ),
              )
            else
              ...players.map(
                (player) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(
                        player.isGoalkeeper
                            ? Icons.sports_handball
                            : Icons.sports_soccer,
                      ),
                    ),
                    title: Text(player.fullName),
                    subtitle: Text(
                      [
                        if (player.isGoalkeeper) 'Gardien',
                        if (!player.isActive) 'Archivé',
                      ].join(' · '),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) async {
                        final repo = ref.read(rosterRepositoryProvider);
                        try {
                          if (action == 'edit') {
                            await _showPlayerDialog(context, ref,
                                seasonId: seasonId, existing: player);
                            return;
                          }
                          if (action == 'delete') {
                            final confirmed =
                                await _confirmDelete(context, player);
                            if (!confirmed) return;
                            await repo.deletePlayer(player.id);
                          } else if (action == 'archive') {
                            await repo.setActive(id: player.id, active: false);
                          } else if (action == 'restore') {
                            await repo.setActive(id: player.id, active: true);
                          }
                          ref.invalidate(rosterProvider(seasonId));
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(humanizeError(error))),
                            );
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Modifier'),
                        ),
                        PopupMenuItem(
                          value: player.isActive ? 'archive' : 'restore',
                          child:
                              Text(player.isActive ? 'Archiver' : 'Réactiver'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Supprimer'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<bool> _confirmDelete(BuildContext context, RosterPlayer player) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Supprimer ${player.displayName} ?'),
          content: const Text(
            'Le joueur est retiré définitivement de l’effectif. Ses buts, '
            'clean sheets et les pronostics de saison le concernant sont '
            'également supprimés. Pour simplement le sortir sans rien effacer, '
            'utilise plutôt « Archiver ».',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Supprimer'),
            ),
          ],
        ),
      ) ??
      false;
}

Future<void> _showPlayerDialog(
  BuildContext context,
  WidgetRef ref, {
  required String seasonId,
  RosterPlayer? existing,
}) async {
  final firstName = TextEditingController(text: existing?.firstName ?? '');
  final lastName = TextEditingController(text: existing?.lastName ?? '');
  var isGoalkeeper = existing?.isGoalkeeper ?? false;
  var saving = false;
  String? error;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(existing == null ? 'Ajouter un joueur' : 'Modifier'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: firstName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Prénom'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: lastName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nom'),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Gardien'),
                value: isGoalkeeper,
                onChanged: saving
                    ? null
                    : (value) => setState(() => isGoalkeeper = value),
              ),
              if (error != null)
                Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    setState(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      final repo = ref.read(rosterRepositoryProvider);
                      if (existing == null) {
                        await repo.addPlayer(
                          seasonId: seasonId,
                          firstName: firstName.text,
                          lastName: lastName.text,
                          isGoalkeeper: isGoalkeeper,
                        );
                      } else {
                        await repo.updatePlayer(
                          id: existing.id,
                          firstName: firstName.text,
                          lastName: lastName.text,
                          isGoalkeeper: isGoalkeeper,
                        );
                      }
                      ref.invalidate(rosterProvider(seasonId));
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    } catch (exception) {
                      setState(() {
                        saving = false;
                        error = humanizeError(exception);
                      });
                    }
                  },
            child: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );

  firstName.dispose();
  lastName.dispose();
}
