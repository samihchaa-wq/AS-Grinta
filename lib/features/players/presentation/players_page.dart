import 'package:as_grinta/features/players/data/players_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Page admin des joueurs indépendants ─────────────────────────────────────

class PlayersPage extends ConsumerWidget {
  const PlayersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playersAsync = ref.watch(playersListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registre des joueurs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: () => ref.invalidate(playersListProvider),
          ),
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Ajouter un joueur',
            onPressed: () => _showCreateDialog(context, ref),
          ),
        ],
      ),
      body: playersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(
          error: error.toString(),
          onRetry: () => ref.invalidate(playersListProvider),
        ),
        data: (players) => players.isEmpty
            ? _EmptyView(onAdd: () => _showCreateDialog(context, ref))
            : RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(playersListProvider);
                  await ref.read(playersListProvider.future);
                },
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: players.length,
                  itemBuilder: (_, i) => _PlayerCard(
                    player: players[i],
                    onRefresh: () => ref.invalidate(playersListProvider),
                  ),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Ajouter un joueur'),
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _CreatePlayerDialog(
        onCreated: () => ref.invalidate(playersListProvider),
      ),
    );
  }
}

// ─── Carte joueur ─────────────────────────────────────────────────────────────

class _PlayerCard extends ConsumerWidget {
  const _PlayerCard({required this.player, required this.onRefresh});
  final PlayerItem player;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(playersRepositoryProvider);
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: player.isGoalkeeper
                      ? const Color(0xFFFF6F00).withOpacity(0.15)
                      : cs.primaryContainer,
                  child: Icon(
                    player.isGoalkeeper
                        ? Icons.sports_handball
                        : Icons.sports_soccer,
                    color: player.isGoalkeeper
                        ? const Color(0xFFFF6F00)
                        : cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        player.fullName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Row(
                        children: [
                          if (player.isGoalkeeper)
                            _Badge(
                              label: 'Gardien',
                              color: const Color(0xFFFF6F00),
                            ),
                          if (player.isClaimed) ...[
                            if (player.isGoalkeeper) const SizedBox(width: 4),
                            _Badge(
                              label: 'Revendiqué',
                              color: cs.primary,
                            ),
                          ] else ...[
                            if (player.isGoalkeeper) const SizedBox(width: 4),
                            _Badge(
                              label: 'Non revendiqué',
                              color: cs.outline,
                            ),
                          ],
                          if (!player.isActive) ...[
                            const SizedBox(width: 4),
                            _Badge(
                              label: 'Archivé',
                              color: cs.error,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (action) =>
                      _handleAction(action, context, ref, repo),
                  itemBuilder: (_) => [
                    if (!player.isClaimed) ...[
                      const PopupMenuItem(
                        value: 'generate_token',
                        child: ListTile(
                          leading: Icon(Icons.link),
                          title: Text('Générer un lien de revendication'),
                          dense: true,
                        ),
                      ),
                    ],
                    if (player.hasActiveToken) ...[
                      const PopupMenuItem(
                        value: 'revoke_token',
                        child: ListTile(
                          leading: Icon(Icons.link_off),
                          title: Text('Révoquer le token'),
                          dense: true,
                        ),
                      ),
                    ],
                    if (player.isActive) ...[
                      const PopupMenuItem(
                        value: 'archive',
                        child: ListTile(
                          leading: Icon(Icons.archive_outlined),
                          title: Text('Archiver'),
                          dense: true,
                        ),
                      ),
                    ] else ...[
                      const PopupMenuItem(
                        value: 'restore',
                        child: ListTile(
                          leading: Icon(Icons.unarchive_outlined),
                          title: Text('Restaurer'),
                          dense: true,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            // Token actif
            if (player.hasActiveToken) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(Icons.key, size: 16, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        player.claimToken ?? '',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: cs.primary,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: 'Copier le token',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: player.claimToken ?? ''));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Token copié dans le presse-papier.'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (player.claimExpiresAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Expire le ${_formatDate(player.claimExpiresAt!)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Future<void> _handleAction(
    String action,
    BuildContext context,
    WidgetRef ref,
    PlayersRepository repo,
  ) async {
    try {
      switch (action) {
        case 'generate_token':
          final token = await repo.generateClaimToken(player.id);
          onRefresh();
          if (context.mounted) {
            await showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Token de revendication généré'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Transmettez ce token au joueur pour qu\'il puisse lier son compte :',
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      token,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Le lien expire dans 7 jours.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                actions: [
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: token));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Token copié.')),
                      );
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copier'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Fermer'),
                  ),
                ],
              ),
            );
          }

        case 'revoke_token':
          await repo.revokeClaimToken(player.id);
          onRefresh();

        case 'archive':
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Archiver le joueur ?'),
              content: Text('${player.fullName} sera masqué de la liste active.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Archiver'),
                ),
              ],
            ),
          );
          if (ok == true) {
            await repo.archivePlayer(player.id);
            onRefresh();
          }

        case 'restore':
          await repo.restorePlayer(player.id);
          onRefresh();
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

// ─── Dialogue de création ─────────────────────────────────────────────────────

class _CreatePlayerDialog extends ConsumerStatefulWidget {
  const _CreatePlayerDialog({required this.onCreated});
  final VoidCallback onCreated;

  @override
  ConsumerState<_CreatePlayerDialog> createState() =>
      _CreatePlayerDialogState();
}

class _CreatePlayerDialogState extends ConsumerState<_CreatePlayerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  bool _isGoalkeeper = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSubmitting = true);

    try {
      await ref.read(playersRepositoryProvider).createPlayer(
            firstName: _firstNameCtrl.text,
            lastName: _lastNameCtrl.text,
            isGoalkeeper: _isGoalkeeper,
          );
      widget.onCreated();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter un joueur'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _firstNameCtrl,
              decoration: const InputDecoration(labelText: 'Prénom *'),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _lastNameCtrl,
              decoration: const InputDecoration(labelText: 'Nom *'),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Gardien de but'),
              value: _isGoalkeeper,
              onChanged: (v) => setState(() => _isGoalkeeper = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Créer'),
        ),
      ],
    );
  }
}

// ─── Widgets utilitaires ──────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.group_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            'Aucun joueur dans le registre',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Ajoutez des joueurs indépendants pour les associer\nà des comptes via un token de revendication.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Ajouter le premier joueur'),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              error.contains('relation') || error.contains('does not exist')
                  ? 'La table "players" n\'existe pas encore dans Supabase.\n'
                      'Appliquez les migrations pour activer cette fonctionnalité.'
                  : error,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Page de revendication de profil (accessible depuis /claim) ───────────────

class ClaimPlayerPage extends ConsumerStatefulWidget {
  const ClaimPlayerPage({super.key, this.token});
  final String? token;

  @override
  ConsumerState<ClaimPlayerPage> createState() => _ClaimPlayerPageState();
}

class _ClaimPlayerPageState extends ConsumerState<ClaimPlayerPage> {
  late final TextEditingController _tokenCtrl;
  bool _isSubmitting = false;
  String? _error;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _tokenCtrl = TextEditingController(text: widget.token ?? '');
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _claim() async {
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Veuillez entrer un token de revendication.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final repo = ref.read(playersRepositoryProvider);
      final profileId = repo.currentUserId;
      if (profileId == null) {
        setState(() => _error = 'Vous devez être connecté pour revendiquer un profil.');
        return;
      }
      await repo.claimProfile(token: token, profileId: profileId);
      if (mounted) setState(() => _success = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_success) {
      return Scaffold(
        appBar: AppBar(title: const Text('Revendication')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Profil revendiqué avec succès !',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Votre compte est maintenant lié à votre fiche joueur.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Retour'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Revendiquer un profil joueur')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lier mon compte à ma fiche joueur',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Entrez le token fourni par votre coach pour associer '
                  'votre compte à votre fiche joueur dans le registre.',
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _tokenCtrl,
                  decoration: InputDecoration(
                    labelText: 'Token de revendication',
                    hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.key),
                    errorText: _error,
                  ),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSubmitting ? null : _claim,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Revendiquer'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
