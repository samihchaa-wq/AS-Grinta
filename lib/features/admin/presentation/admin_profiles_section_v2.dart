part of 'admin_page.dart';

final _adminHistoricalPlayersProvider =
    FutureProvider<List<AdminHistoricalPlayer>>((ref) {
  return ref.watch(adminRepositoryProvider).fetchHistoricalPlayers();
});

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
                onSelected: (_) {
                  if (role.value == selected.value) return;
                  onSelected(role.value);
                },
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
    final historicalPlayersState = ref.watch(_adminHistoricalPlayersProvider);
    final historicalPlayers = historicalPlayersState.asData?.value;
    AdminHistoricalPlayer? historicalPlayer;
    if (historicalPlayers != null) {
      for (final player in historicalPlayers) {
        if (player.linkedProfileId == profile.id) {
          historicalPlayer = player;
          break;
        }
      }
    }

    Future<void> run(Future<void> Function() action, {String? success}) async {
      try {
        await action();
        ref.invalidate(adminDashboardProvider);
        if (success != null && context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(success)));
        }
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(humanizeError(error))));
        }
      }
    }

    Widget validatedDetails() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (profile.username.trim().isNotEmpty)
            Text('Identifiant : ${profile.username}'),
          Text(
            historicalPlayers == null
                ? 'Rattachement : …'
                : historicalPlayer == null
                    ? 'Rattachement : aucun'
                    : 'Rattachement : ${historicalPlayer.name}',
          ),
          if (!policy.isSelf) ...[
            const SizedBox(height: 10),
            _RoleChoice(
              current: profile.role,
              onSelected: (role) => run(
                () => repository.updateProfileRole(profile.id, role),
                success: 'Accès de ${profile.displayName} mis à jour.',
              ),
            ),
          ],
          if (!profile.passwordSet)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Chip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(Icons.hourglass_top, size: 16),
                label: Text('En attente de 1re connexion'),
              ),
            ),
          if (!policy.isSelf) ...[
            const SizedBox(height: 8),
            _ValidatedProfileActions(
              profile: profile,
              archived: policy.isArchived,
              onResetPassword: () =>
                  _resetPassword(context, ref, repository, profile),
              onHistory: () async {
                final choice = await _pickHistorical(
                  context,
                  repository,
                  profileId: profile.id,
                );
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
                ref.invalidate(_adminHistoricalPlayersProvider);
              },
              onArchiveToggle: () async {
                final nextStatus = policy.isArchived ? 'active' : 'archived';
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
                  () => repository.updateProfileStatus(profile.id, nextStatus),
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
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: policy.isPending
          ? Padding(
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
                    ],
                  ),
                  if (profile.username.trim().isNotEmpty)
                    Text('Identifiant : ${profile.username}'),
                  if (!policy.isSelf) ...[
                    const SizedBox(height: 6),
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
                    ),
                  ],
                ],
              ),
            )
          : ExpansionTile(
              key: PageStorageKey<String>('validated-profile-${profile.id}'),
              initiallyExpanded: false,
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              title: Text(
                profile.displayName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (policy.isSelf)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: _StatusChip(label: 'Toi'),
                    )
                  else if (policy.isArchived)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: _StatusChip(label: 'Archivé'),
                    ),
                  const Icon(Icons.expand_more),
                ],
              ),
              children: [validatedDetails()],
            ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      container: true,
      child: ExcludeSemantics(
        child: Chip(visualDensity: VisualDensity.compact, label: Text(label)),
      ),
    );
  }
}
