part of 'admin_page.dart';

final _adminHistoricalPlayersProvider =
    FutureProvider<List<AdminHistoricalPlayer>>((ref) {
  return ref.watch(adminRepositoryProvider).fetchHistoricalPlayers();
});

// Les trois actions « Modifier » ont un contraste lisible sur le fond nuit.
class _MemberEditButton extends StatelessWidget {
  const _MemberEditButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF1464EF),
        foregroundColor: Colors.white,
        disabledBackgroundColor:
            Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 38),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: onPressed,
      child: const Text('Modifier'),
    );
  }
}

class _MemberDetailRow extends StatelessWidget {
  const _MemberDetailRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 112, child: Text(label)),
          const SizedBox(width: 6),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _MemberValue extends StatelessWidget {
  const _MemberValue(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
        color: scheme.surfaceContainerHighest.withValues(alpha: .46),
      ),
      child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
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
  late final TextEditingController _firstNameController;
  bool _savingFirstName = false;

  String get _rosterFirstName =>
      widget.rosterPlayer?.firstName ?? widget.profile.firstName;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(text: _rosterFirstName);
  }

  @override
  void didUpdateWidget(covariant _ProfileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous =
        oldWidget.rosterPlayer?.firstName ?? oldWidget.profile.firstName;
    if (previous != _rosterFirstName) {
      _firstNameController.text = _rosterFirstName;
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    super.dispose();
  }

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

    Future<void> saveFirstName() async {
      final player = rosterPlayer;
      final currentEffectif = effectif;
      if (player == null || currentEffectif == null || _savingFirstName) return;
      final name = _firstNameController.text.trim();
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Le prénom est obligatoire.')),
        );
        return;
      }
      if (name == player.firstName.trim()) return;
      setState(() => _savingFirstName = true);
      try {
        await ref.read(rosterRepositoryProvider).updatePlayer(
              id: player.id,
              firstName: name,
              isGoalkeeper: player.isGoalkeeper,
              isCoach: player.isCoach,
            );
        ref.invalidate(rosterProvider(currentEffectif.seasonId));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Prénom de la fiche joueur enregistré.')),
          );
        }
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(humanizeError(error))),
          );
        }
      } finally {
        if (mounted) setState(() => _savingFirstName = false);
      }
    }

    Future<void> updatePlayerRole({
      required bool isGoalkeeper,
      required bool isCoach,
    }) async {
      final player = rosterPlayer;
      final currentEffectif = effectif;
      if (player == null || currentEffectif == null || policy.isArchived) {
        return;
      }
      await run(() async {
        await ref.read(rosterRepositoryProvider).updatePlayer(
              id: player.id,
              firstName: player.firstName,
              isGoalkeeper: isGoalkeeper,
              isCoach: isCoach,
            );
        ref.invalidate(rosterProvider(currentEffectif.seasonId));
      });
    }

    Future<void> modifyHistoricalLink() async {
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
    }

    Future<void> archiveAccount() async {
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
        success: policy.isArchived ? 'Compte réactivé.' : 'Compte archivé.',
      );
    }

    Future<void> deleteAccount() async {
      final confirmed = await _confirm(
        context,
        'Supprimer ce compte ?',
        '${profile.displayName} sera supprimé définitivement. '
            'Pour bloquer uniquement la connexion, utilise « Archiver ».',
      );
      if (!confirmed) return;
      await run(
        () => repository.deleteAccount(profile.id),
        success: 'Compte supprimé.',
      );
    }

    Widget validatedDetails() {
      final player = rosterPlayer;
      final currentEffectif = effectif;
      final canEditRoster = player != null &&
          currentEffectif != null &&
          !policy.isArchived &&
          !_savingFirstName;
      final editedName = _firstNameController.text.trim();
      final nameChanged =
          player != null && editedName != player.firstName.trim();

      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Prénom'),
                      const SizedBox(height: 6),
                      if (player == null)
                        _MemberValue(profile.firstName)
                      else
                        TextField(
                          key: ValueKey<String>(
                              'effectif-first-name-${profile.id}'),
                          controller: _firstNameController,
                          enabled: canEditRoster,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.done,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => saveFirstName(),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Identifiant'),
                      const SizedBox(height: 6),
                      _MemberValue(
                        profile.username.isEmpty ? '—' : profile.username,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (nameChanged && canEditRoster)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: saveFirstName,
                  child: const Text('Enregistrer le prénom'),
                ),
              ),
            const Divider(height: 16),
            _MemberDetailRow(
              label: 'Rattachement',
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      historicalPlayers == null
                          ? 'Chargement…'
                          : historicalPlayer?.name ?? 'Aucun',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (!policy.isSelf)
                    _MemberEditButton(onPressed: modifyHistoricalLink),
                ],
              ),
            ),
            const Divider(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Rôle'),
            ),
            Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: FilterChip(
                      key: const ValueKey('role-effectif'),
                      label: const Text('Effectif'),
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      labelPadding: EdgeInsets.zero,
                      selected: inRoster,
                      onSelected: currentEffectif == null ||
                              (policy.isArchived && !inRoster)
                          ? null
                          : (_) => toggleRoster(currentEffectif),
                    ),
                  ),
                ),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: FilterChip(
                      key: const ValueKey('role-admin'),
                      label: const Text('Admin'),
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      labelPadding: EdgeInsets.zero,
                      selected: profile.role == 'admin',
                      onSelected: policy.isSelf || policy.isArchived
                          ? null
                          : (_) => run(
                                () => repository.updateProfileRole(
                                  profile.id,
                                  profile.role == 'admin'
                                      ? 'pronostiqueur'
                                      : 'admin',
                                ),
                                success:
                                    'Accès de ${profile.displayName} mis à jour.',
                              ),
                    ),
                  ),
                ),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: FilterChip(
                      key: const ValueKey('role-gardien'),
                      label: const Text('Gardien'),
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      labelPadding: EdgeInsets.zero,
                      selected: player?.isGoalkeeper ?? false,
                      onSelected: !canEditRoster
                          ? null
                          : (_) => updatePlayerRole(
                                isGoalkeeper: !player.isGoalkeeper,
                                isCoach: false,
                              ),
                    ),
                  ),
                ),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: FilterChip(
                      key: const ValueKey('role-coach'),
                      label: const Text('Coach'),
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      labelPadding: EdgeInsets.zero,
                      selected: player?.isCoach ?? false,
                      onSelected: !canEditRoster
                          ? null
                          : (_) => updatePlayerRole(
                                isGoalkeeper: false,
                                isCoach: !player.isCoach,
                              ),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text('Photo'),
                      const SizedBox(height: 8),
                      _MemberEditButton(
                        onPressed: player == null || currentEffectif == null
                            ? null
                            : () => chooseRosterPhoto(
                                  context,
                                  ref,
                                  seasonId: currentEffectif.seasonId,
                                  player: player,
                                ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    children: [
                      const Text('Mot de passe'),
                      const SizedBox(height: 8),
                      _MemberEditButton(
                        onPressed: policy.isSelf || policy.isArchived
                            ? null
                            : () => _resetPassword(
                                  context,
                                  ref,
                                  repository,
                                  profile,
                                ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!profile.passwordSet)
              const Text('Première connexion en attente'),
            if (!policy.isSelf) ...[
              const Divider(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: archiveAccount,
                      child: Text(policy.isArchived ? 'Réactiver' : 'Archiver'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: Theme.of(context).colorScheme.onError,
                      ),
                      onPressed: deleteAccount,
                      child: const Text('Supprimer'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
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
              key: ValueKey<String>('validated-profile-${profile.id}'),
              initiallyExpanded: false,
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
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
              // La ligne repliée ne montre que le portrait et le nom.
              // Toute la ligne reste tactile pour ouvrir les options.
              trailing: const SizedBox.shrink(),
              children: [validatedDetails()],
            ),
    );
  }
}
