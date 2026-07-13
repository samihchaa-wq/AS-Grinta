part of 'admin_page.dart';

class _ProfilesSection extends StatelessWidget {
  const _ProfilesSection({
    required this.title,
    required this.profiles,
    required this.emptyMessage,
    required this.icon,
  });

  final String title;
  final List<AdminProfileItem> profiles;
  final String emptyMessage;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text('${profiles.length}'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (profiles.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(emptyMessage)),
                ],
              ),
            ),
          )
        else
          ...profiles.map((profile) => _ProfileCard(profile: profile)),
      ],
    );
  }
}

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard({required this.profile});

  final AdminProfileItem profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.read(adminRepositoryProvider);
    final currentUserId = ref.watch(authControllerProvider).profile?.id;
    final policy = adminProfileActionPolicy(
      profile: profile,
      currentUserId: currentUserId,
    );

    Future<void> run(Future<void> Function() action, {String? success}) async {
      try {
        await action();
        ref.invalidate(adminDashboardProvider);
        if (success != null && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(success)));
        }
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
        }
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    profile.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (policy.isSelf)
                  const Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('Toi'),
                  )
                else if (policy.isArchived)
                  const Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('Archivé'),
                  ),
              ],
            ),
            if (profile.username.trim().isNotEmpty)
              Text('Identifiant : ${profile.username}'),
            if (!profile.passwordSet && !policy.isPending)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.hourglass_top, size: 16),
                  label: const Text('En attente de 1re connexion'),
                ),
              ),
            // Actions réservées aux autres comptes : l'admin ne se gère pas
            // lui-même.
            if (!policy.isSelf) ...[
              if (policy.isPending) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => run(
                      () =>
                          repository.updateProfileStatus(profile.id, 'active'),
                      success:
                          '${profile.displayName} peut maintenant se connecter.',
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Valider ce compte'),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: () async {
                      final confirmed = await _confirm(
                        context,
                        'Refuser et supprimer ce compte ?',
                        '${profile.displayName} sera supprimé définitivement. '
                            'Cette action est irréversible.',
                      );
                      if (!confirmed) return;
                      await run(
                        () => repository.deleteAccount(profile.id),
                        success: 'Compte supprimé.',
                      );
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Refuser et supprimer'),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final confirmed = await _confirm(
                          context,
                          'Réinitialiser le mot de passe ?',
                          '${profile.displayName} devra refaire une '
                              '« première connexion ».',
                        );
                        if (!confirmed) return;
                        await run(
                          () => repository.resetAccountPassword(profile.id),
                          success: 'Mot de passe réinitialisé.',
                        );
                      },
                      icon: const Icon(Icons.lock_reset, size: 18),
                      label: const Text('Réinitialiser le mot de passe'),
                    ),
                    if (policy.isArchived)
                      TextButton.icon(
                        onPressed: () => run(
                          () => repository.updateProfileStatus(
                            profile.id,
                            'active',
                          ),
                          success: 'Compte réactivé.',
                        ),
                        icon: const Icon(Icons.unarchive_outlined, size: 18),
                        label: const Text('Réactiver'),
                      )
                    else
                      TextButton.icon(
                        onPressed: () async {
                          final confirmed = await _confirm(
                            context,
                            'Archiver ce compte ?',
                            '${profile.displayName} ne pourra plus se '
                                'connecter. Ses pronostics sont conservés.',
                          );
                          if (!confirmed) return;
                          await run(
                            () => repository.updateProfileStatus(
                              profile.id,
                              'archived',
                            ),
                            success: 'Compte archivé.',
                          );
                        },
                        icon: const Icon(Icons.archive_outlined, size: 18),
                        label: const Text('Archiver'),
                      ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: () async {
                        final confirmed = await _confirm(
                          context,
                          'Supprimer ce compte ?',
                          '${profile.displayName} sera supprimé '
                              'définitivement, ainsi que tous ses pronostics. '
                              'Cette action est irréversible. Pour juste '
                              'l’empêcher de se connecter, utilise plutôt '
                              '« Archiver ».',
                        );
                        if (!confirmed) return;
                        await run(
                          () => repository.deleteAccount(profile.id),
                          success: 'Compte supprimé.',
                        );
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Supprimer'),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(
    BuildContext context,
    String title,
    String message,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
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
}
