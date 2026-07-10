import 'package:as_grinta/features/players/data/players_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PlayersRegistryPage extends ConsumerWidget {
  const PlayersRegistryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playersAsync = ref.watch(playersListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registre des joueurs'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () => ref.invalidate(playersListProvider),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Ajouter un joueur permanent',
            onPressed: () => _showCreateDialog(context, ref),
            icon: const Icon(Icons.person_add_outlined),
          ),
        ],
      ),
      body: playersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _RegistryUnavailable(
          onRetry: () => ref.invalidate(playersListProvider),
        ),
        data: (players) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(playersListProvider);
            await ref.read(playersListProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              const Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Joueurs permanents'),
                  subtitle: Text(
                    'Les invités temporaires sont ajoutés uniquement dans la feuille de match post-match. '
                    'Ils ne sont jamais enregistrés dans ce registre ni dans les statistiques de carrière.',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (players.isEmpty)
                const _EmptyRegistry()
              else
                ...players.map(
                  (player) => _PlayerCard(
                    player: player,
                    onChanged: () => ref.invalidate(playersListProvider),
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Joueur permanent'),
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final firstName = TextEditingController();
    final lastName = TextEditingController();
    final nickname = TextEditingController();
    var isGoalkeeper = false;
    var saving = false;
    String? error;

    await showDialog<void>(
      context: context,
      barrierDismissible: !saving,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Ajouter un joueur permanent'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nickname,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Surnom',
                    helperText: 'Facultatif — nom affiché dans l’application',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: firstName,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Prénom *'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: lastName,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(labelText: 'Nom *'),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Gardien de but'),
                  value: isGoalkeeper,
                  onChanged: saving
                      ? null
                      : (value) =>
                          setDialogState(() => isGoalkeeper = value),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
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
                      if (firstName.text.trim().isEmpty ||
                          lastName.text.trim().isEmpty) {
                        setDialogState(
                          () => error = 'Le prénom et le nom sont obligatoires.',
                        );
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await ref.read(playersRepositoryProvider).createPlayer(
                              firstName: firstName.text,
                              lastName: lastName.text,
                              surnom: nickname.text,
                              isGoalkeeper: isGoalkeeper,
                            );
                        ref.invalidate(playersListProvider);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (_) {
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            saving = false;
                            error = 'Le joueur n’a pas pu être créé.';
                          });
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Créer'),
            ),
          ],
        ),
      ),
    );

    firstName.dispose();
    lastName.dispose();
    nickname.dispose();
  }
}

class _PlayerCard extends ConsumerWidget {
  const _PlayerCard({required this.player, required this.onChanged});

  final PlayerItem player;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            player.isGoalkeeper
                ? Icons.sports_handball
                : Icons.sports_soccer,
          ),
        ),
        title: Text(player.displayName),
        subtitle: Text(
          [
            player.fullName,
            player.isGoalkeeper ? 'Gardien' : 'Joueur',
            player.isClaimed ? 'Compte lié' : 'Compte non lié',
            if (!player.isActive) 'Archivé',
          ].where((value) => value.trim().isNotEmpty).join(' · '),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) => _handleAction(context, ref, action),
          itemBuilder: (context) => [
            if (!player.isClaimed)
              const PopupMenuItem(
                value: 'link',
                child: Text('Créer un lien de rattachement'),
              ),
            if (player.hasActiveToken)
              const PopupMenuItem(
                value: 'revoke',
                child: Text('Révoquer le lien'),
              ),
            PopupMenuItem(
              value: player.isActive ? 'archive' : 'restore',
              child: Text(player.isActive ? 'Archiver' : 'Restaurer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    final repository = ref.read(playersRepositoryProvider);
    try {
      switch (action) {
        case 'link':
          final token = await repository.generateClaimToken(player.id);
          final link = Uri.base.resolve('claim?token=$token').toString();
          onChanged();
          if (context.mounted) await _showLink(context, link);
        case 'revoke':
          await repository.revokeClaimToken(player.id);
          onChanged();
        case 'archive':
          if (await _confirm(context, 'Archiver ce joueur ?')) {
            await repository.archivePlayer(player.id);
            onChanged();
          }
        case 'restore':
          await repository.restorePlayer(player.id);
          onChanged();
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('L’opération n’a pas pu être effectuée.'),
          ),
        );
      }
    }
  }

  Future<bool> _confirm(BuildContext context, String title) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirmer'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showLink(BuildContext context, String link) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lien de rattachement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Le joueur active d’abord le compte reçu par email, puis ouvre ce lien pour rattacher sa fiche.',
            ),
            const SizedBox(height: 12),
            SelectableText(link),
            const SizedBox(height: 8),
            const Text('Ce lien expire dans 7 jours.'),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Lien copié.')),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copier'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}

class _EmptyRegistry extends StatelessWidget {
  const _EmptyRegistry();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.group_outlined, size: 48),
            SizedBox(height: 12),
            Text('Aucun joueur permanent enregistré.'),
          ],
        ),
      ),
    );
  }
}

class _RegistryUnavailable extends StatelessWidget {
  const _RegistryUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 52,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              'Registre temporairement indisponible',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Actualise dans quelques instants.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualiser'),
            ),
          ],
        ),
      ),
    );
  }
}
