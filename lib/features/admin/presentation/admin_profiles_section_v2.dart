part of 'admin_page.dart';

final _adminHistoricalPlayersProvider =
    FutureProvider<List<AdminHistoricalPlayer>>((ref) {
  return ref.watch(adminRepositoryProvider).fetchHistoricalPlayers();
});

class _RoleChoice extends StatelessWidget {
  const _RoleChoice({required this.current, required this.onSelected});

  final String current;
  final ValueChanged<String> onSelected;

  static const _roles = <({String value, String label})>[
    (value: 'pronostiqueur', label: 'Utilisateur'),
    (value: 'admin', label: 'Admin'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        const Text('Rôle :'),
        for (final role in _roles)
          ChoiceChip(
            visualDensity: VisualDensity.compact,
            label: Text(role.label),
            selected: role.value == current,
            onSelected: (_) {
              if (role.value != current) onSelected(role.value);
            },
          ),
      ],
    );
  }
}

class _ProfileCard extends ConsumerStatefulWidget {
  const _ProfileCard({
    required this.profile,
    this.effectif,
    this.rosterPlayer,
  });

  final AdminProfileItem profile;

  /// Null tant que l'effectif charge, ou s'il n'y a pas de saison ouverte.
  final _EffectifContext? effectif;

  /// Fiche de l'effectif reliée à ce compte, s'il en a une.
  final RosterPlayer? rosterPlayer;

  @override
  ConsumerState<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends ConsumerState<_ProfileCard> {
  bool _expanded = false;

  AdminProfileItem get profile => widget.profile;
  _EffectifContext? get effectif => widget.effectif;
  RosterPlayer? get rosterPlayer => widget.rosterPlayer;

  @override
  Widget build(BuildContext context) {
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

    final inRoster = rosterPlayer?.isActive ?? false;

    Future<void> toggleRoster(_EffectifContext effectif) async {
      final rosterRepository = ref.read(rosterRepositoryProvider);
      if (inRoster) {
        final confirmed = await _confirm(
          context,
          'Retirer de l’effectif ?',
          '${profile.displayName} ne fera plus partie de l’effectif de la '
              'saison. Son compte, ses statistiques et son historique sont '
              'conservés.',
        );
        if (!confirmed) return;
      }
      await run(
        () async {
          if (inRoster) {
            await rosterRepository.setActive(
              id: rosterPlayer!.id,
              active: false,
            );
          } else {
            await rosterRepository.addProfileToRoster(
              seasonId: effectif.seasonId,
              profileId: profile.id,
              firstName: profile.firstName.trim().isNotEmpty
                  ? profile.firstName
                  : profile.displayName,
              existingSeasonPlayerId: rosterPlayer?.id,
            );
          }
          ref.invalidate(rosterProvider(effectif.seasonId));
        },
        success: inRoster
            ? '${profile.displayName} est retiré de l’effectif.'
            : '${profile.displayName} est ajouté à l’effectif.',
      );
    }

    Widget effectifDetails(_EffectifContext effectif) {
      final player = rosterPlayer;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 16),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              const Text('Effectif :'),
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                label: const Text('Oui'),
                selected: inRoster,
                onSelected: (_) {
                  if (!inRoster && !policy.isArchived) {
                    toggleRoster(effectif);
                  }
                },
              ),
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                label: const Text('Non'),
                selected: !inRoster,
                onSelected: (_) {
                  if (inRoster) toggleRoster(effectif);
                },
              ),
              if (inRoster && player!.isCoach) const Text('Coach'),
              if (inRoster && player!.isGoalkeeper) const Text('Gardien'),
            ],
          ),
          if (inRoster)
            Row(
              children: [
                TextButton(
                  onPressed: () => showRosterPlayerDialog(
                    context,
                    ref,
                    seasonId: effectif.seasonId,
                    existing: player,
                  ),
                  child: const Text('Poste'),
                ),
                TextButton(
                  onPressed: () => chooseRosterPhoto(
                    context,
                    ref,
                    seasonId: effectif.seasonId,
                    player: player!,
                  ),
                  child: const Text('Photos'),
                ),
              ],
            ),
        ],
      );
    }

    Widget validatedDetails() {
      final currentEffectif = effectif;
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
            const SizedBox(height: 6),
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
              child: Text('Première connexion en attente'),
            ),
          if (currentEffectif != null) effectifDetails(currentEffectif),
          if (!policy.isSelf) ...[
            const Divider(height: 16),
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
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              onExpansionChanged: (expanded) =>
                  setState(() => _expanded = expanded),
              leading: rosterPlayer == null
                  ? null
                  : PlayerAvatar(
                      photoUrl: rosterPlayer!.photoUrl,
                      name: rosterPlayer!.displayName,
                      lastName: rosterPlayer!.lastName,
                      isGoalkeeper: rosterPlayer!.isGoalkeeper,
                      size: 40,
                    ),
              title: Text(
                profile.displayName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                [
                  if (profile.username.trim().isNotEmpty) profile.username,
                  profile.role == 'admin' ? 'Admin' : 'Utilisateur',
                  if (policy.isSelf) 'Toi',
                  if (policy.isArchived) 'Archivé',
                  if (effectif != null && !inRoster && !policy.isArchived)
                    'Hors effectif',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                _expanded ? 'Fermer' : 'Modifier',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
              children: [validatedDetails()],
            ),
    );
  }
}

