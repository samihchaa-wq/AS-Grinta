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
            // `onSelected: null` désactivait la puce du rôle EN VIGUEUR, que
            // Material grisait alors : le rôle actif avait l'apparence d'un
            // état indisponible, et le rôle inactif celle du rôle courant. La
            // puce reste donc active et un nouveau clic sur le rôle déjà
            // sélectionné est simplement ignoré.
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
                // Étiquettes purement informatives : un Chip Material expose
                // une sémantique sélectionnable, qu'un lecteur d'écran
                // annonçait comme une case à cocher inexistante.
                if (policy.isSelf)
                  const _StatusChip(label: 'Toi')
                else if (policy.isArchived)
                  const _StatusChip(label: 'Archivé'),
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
                    final nextStatus = policy.isArchived
                        ? 'active'
                        : 'archived';
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
}

/// Étiquette d'état non interactive.
///
/// Un [Chip] Material porte une sémantique de sélection : sur l'écran Comptes,
/// la pastille « Toi » était annoncée comme une case à cocher. On masque donc
/// la sémantique du Chip et on la remplace par un simple libellé.
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
