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

class _ProfileValidationChoice {
  const _ProfileValidationChoice({
    required this.seasonPlayerId,
    required this.seasonId,
  });

  final String? seasonPlayerId;
  final String? seasonId;
}

class _HistoricalChoice {
  const _HistoricalChoice(this.historicalId);

  final int? historicalId;
}

class _RoleChoice extends StatelessWidget {
  const _RoleChoice({required this.current, required this.onSelected});

  final String current;
  final ValueChanged<String> onSelected;

  static const _roles = <({String value, String label, String hint})>[
    (
      value: 'pronostiqueur',
      label: 'Utilisateur',
      hint: 'Utilise l’application sans droit d’administration.',
    ),
    (
      value: 'admin',
      label: 'Admin',
      hint: 'Accès à tous les outils de gestion du club.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final selected = _roles.firstWhere(
      (role) => role.value == current,
      orElse: () => _roles.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final role in _roles)
              ChoiceChip(
                label: Text(role.label),
                selected: role.value == selected.value,
                onSelected: role.value == selected.value
                    ? null
                    : (_) => onSelected(role.value),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(selected.hint, style: Theme.of(context).textTheme.bodySmall),
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
            if (!policy.isSelf && !policy.isPending) ...[
              const SizedBox(height: 10),
              _RoleChoice(
                current: profile.role,
                onSelected: (role) => run(
                  () => repository.updateProfileRole(profile.id, role),
                  success: 'Accès de ${profile.displayName} mis à jour.',
                ),
              ),
            ],
            if (!profile.passwordSet && !policy.isPending)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.hourglass_top, size: 16),
                  label: Text('En attente de 1re connexion'),
                ),
              ),
            if (!policy.isSelf) ...[
              const SizedBox(height: 10),
              if (policy.isPending)
                _PendingProfileActions(
                  profile: profile,
                  onValidate: () async {
                    final choice = await _askPlayerLink(context, ref);
                    if (choice == null) return;
                    await run(
                      () async {
                        await repository.validateProfile(
                          profile.id,
                          seasonPlayerId: choice.seasonPlayerId,
                        );
                        final seasonId = choice.seasonId;
                        if (seasonId != null) {
                          ref.invalidate(rosterProvider(seasonId));
                        }
                      },
                      success: choice.seasonPlayerId == null
                          ? '${profile.displayName} peut maintenant se connecter.'
                          : '${profile.displayName} est validé et relié au joueur.',
                    );
                  },
                  onReject: () async {
                    final confirmed = await _confirm(
                      context,
                      'Refuser et supprimer ce compte ?',
                      '${profile.displayName} sera supprimé définitivement.',
                    );
                    if (!confirmed) return;
                    await run(
                      () => repository.deleteAccount(profile.id),
                      success: 'Compte supprimé.',
                    );
                  },
                )
              else
                _ValidatedProfileActions(
                  profile: profile,
                  archived: policy.isArchived,
                  onResetPassword: () =>
                      _resetPassword(context, ref, repository, profile),
                  onHistory: () async {
                    final choice = await _pickHistorical(context, repository);
                    if (choice == null) return;
                    await run(
                      () => repository.setHistoricalProfile(
                        profileId: profile.id,
                        historicalId: choice.historicalId,
                      ),
                      success: choice.historicalId == null
                          ? 'Historique détaché de ${profile.displayName}.'
                          : 'Historique rattaché à ${profile.displayName}.',
                    );
                  },
                  onArchiveToggle: () async {
                    final nextStatus =
                        policy.isArchived ? 'active' : 'archived';
                    if (!policy.isArchived) {
                      final confirmed = await _confirm(
                        context,
                        'Archiver ce compte ?',
                        '${profile.displayName} ne pourra plus se connecter. '
                            'Ses données seront conservées.',
                      );
                      if (!confirmed) return;
                    }
                    await run(
                      () => repository.updateProfileStatus(
                        profile.id,
                        nextStatus,
                      ),
                      success: policy.isArchived
                          ? 'Compte réactivé.'
                          : 'Compte archivé.',
                    );
                  },
                  onDelete: () async {
                    final confirmed = await _confirm(
                      context,
                      'Supprimer ce compte ?',
                      '${profile.displayName} sera supprimé définitivement. '
                          'Pour bloquer uniquement la connexion, utilise '
                          '« Archiver ».',
                    );
                    if (!confirmed) return;
                    await run(
                      () => repository.deleteAccount(profile.id),
                      success: 'Compte supprimé.',
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<_ProfileValidationChoice?> _askPlayerLink(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final rosterRepository = ref.read(rosterRepositoryProvider);
    String? seasonId;
    List<RosterPlayer> availablePlayers = const [];
    String? loadingError;

    try {
      seasonId = await rosterRepository.openSeasonId();
      if (seasonId != null) {
        final roster = await rosterRepository.fetchRoster(seasonId);
        availablePlayers = roster
            .where(
              (player) => player.isActive && player.linkedProfileId == null,
            )
            .toList();
      }
    } catch (error) {
      loadingError = humanizeError(error);
    }

    if (!context.mounted) return null;
    var selectedPlayerId = '';

    return showDialog<_ProfileValidationChoice>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Relier à un joueur ?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tu peux associer ce compte à sa fiche joueur maintenant ou '
                'le faire plus tard dans Effectif.',
              ),
              const SizedBox(height: 16),
              if (loadingError != null)
                Text(
                  'Effectif indisponible : $loadingError\n'
                  'Le compte peut quand même être validé.',
                )
              else if (seasonId == null || availablePlayers.isEmpty)
                const Text('Aucun joueur libre à associer actuellement.')
              else
                DropdownButtonFormField<String>(
                  initialValue: selectedPlayerId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Joueur'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Ne pas relier maintenant'),
                    ),
                    ...availablePlayers.map(
                      (player) => DropdownMenuItem(
                        value: player.id,
                        child: Text(player.displayName),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => selectedPlayerId = value ?? '');
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _ProfileValidationChoice(
                  seasonPlayerId:
                      selectedPlayerId.isEmpty ? null : selectedPlayerId,
                  seasonId: seasonId,
                ),
              ),
              child: const Text('Valider'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingProfileActions extends StatelessWidget {
  const _PendingProfileActions({
    required this.profile,
    required this.onValidate,
    required this.onReject,
  });

  final AdminProfileItem profile;
  final VoidCallback onValidate;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: onValidate,
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('Valider ce compte'),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: onReject,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Refuser et supprimer'),
          ),
        ),
      ],
    );
  }
}

class _ValidatedProfileActions extends StatelessWidget {
  const _ValidatedProfileActions({
    required this.profile,
    required this.archived,
    required this.onResetPassword,
    required this.onHistory,
    required this.onArchiveToggle,
    required this.onDelete,
  });

  final AdminProfileItem profile;
  final bool archived;
  final VoidCallback onResetPassword;
  final VoidCallback onHistory;
  final VoidCallback onArchiveToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        TextButton.icon(
          onPressed: onResetPassword,
          icon: const Icon(Icons.lock_reset, size: 18),
          label: const Text('Mot de passe'),
        ),
        TextButton.icon(
          onPressed: onHistory,
          icon: const Icon(Icons.history, size: 18),
          label: const Text('Historique'),
        ),
        TextButton.icon(
          onPressed: onArchiveToggle,
          icon: Icon(
            archived ? Icons.unarchive_outlined : Icons.archive_outlined,
            size: 18,
          ),
          label: Text(archived ? 'Réactiver' : 'Archiver'),
        ),
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Supprimer'),
        ),
      ],
    );
  }
}

Future<void> _resetPassword(
  BuildContext context,
  WidgetRef ref,
  AdminRepository repository,
  AdminProfileItem profile,
) async {
  final confirmed = await _confirm(
    context,
    'Réinitialiser le mot de passe ?',
    'Un lien à usage unique sera généré pour ${profile.displayName}.',
  );
  if (!confirmed) return;

  try {
    final link = await repository.resetAccountPassword(profile.id);
    ref.invalidate(adminDashboardProvider);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lien de réinitialisation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Envoie ce lien à ${profile.displayName} :'),
            const SizedBox(height: 12),
            SelectableText(link),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(
                  dialogContext,
                ).showSnackBar(const SnackBar(content: Text('Lien copié.')));
              }
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copier'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
  }
}

Future<_HistoricalChoice?> _pickHistorical(
  BuildContext context,
  AdminRepository repository,
) async {
  List<AdminHistoricalPlayer> players;
  try {
    players = await repository.fetchHistoricalPlayers();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
    }
    return null;
  }
  if (!context.mounted) return null;

  int? selectedId;
  return showDialog<_HistoricalChoice>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Historique du club'),
        content: SizedBox(
          width: 430,
          child: DropdownButtonFormField<int?>(
            initialValue: selectedId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Fiche historique'),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('Aucun rattachement'),
              ),
              ...players.map(
                (player) => DropdownMenuItem<int?>(
                  value: player.id,
                  child: Text(
                    '${player.name} — ${player.matchesPlayed} matchs, '
                    '${player.goals} buts',
                  ),
                ),
              ),
            ],
            onChanged: (value) => setState(() => selectedId = value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _HistoricalChoice(selectedId)),
            child: const Text('Enregistrer'),
          ),
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
