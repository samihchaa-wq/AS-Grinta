import 'package:as_grinta/features/admin/data/admin_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AdminPage extends ConsumerWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(adminDashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Administration'),
        actions: [
          IconButton(
            tooltip: 'Inviter un compte',
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: () => _showInviteDialog(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(adminDashboardProvider);
          await ref.read(adminDashboardProvider.future);
        },
        child: dashboardAsync.when(
          loading: () => ListView(
            children: [
              SizedBox(height: 220),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(error.toString()),
                ),
              ),
            ],
          ),
          data: (dashboard) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SeasonSection(dashboard: dashboard),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Comptes et effectif',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _showInviteDialog(context, ref),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Inviter'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (dashboard.profiles.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Aucun compte créé pour le moment.'),
                  ),
                )
              else
                ...dashboard.profiles.map(
                  (profile) => _ProfileCard(
                    profile: profile,
                    openSeasonId: dashboard.openSeasonId,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showInviteDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final emailController = TextEditingController();
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    String? error;
    var saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !saving,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Inviter un utilisateur'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: firstNameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Prénom'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: lastNameController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: 'Nom'),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
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
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await ref.read(adminRepositoryProvider).inviteUser(
                              email: emailController.text,
                              firstName: firstNameController.text,
                              lastName: lastNameController.text,
                            );
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        ref.invalidate(adminDashboardProvider);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Invitation envoyée.'),
                          ),
                        );
                      } catch (exception) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          saving = false;
                          error = exception.toString();
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Envoyer'),
            ),
          ],
        ),
      ),
    );

    emailController.dispose();
    firstNameController.dispose();
    lastNameController.dispose();
  }
}

class _SeasonSection extends ConsumerWidget {
  const _SeasonSection({required this.dashboard});

  final AdminDashboardData dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openSeason = dashboard.seasons
        .where((season) => season.status == 'open')
        .cast<AdminSeasonItem?>()
        .firstOrNull;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saisons', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (openSeason == null)
              FilledButton.icon(
                onPressed: () => _showCreateSeasonDialog(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Créer la saison ouverte'),
              )
            else ...[
              Text('Saison ouverte : ${openSeason.name}'),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Archiver la saison ?'),
                      content: Text(
                        'La saison ${openSeason.name} sera clôturée. Les catégories '
                        'des joueurs ayant moins de trois participations seront exclues.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Annuler'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Archiver'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  await ref
                      .read(adminRepositoryProvider)
                      .archiveSeason(openSeason.id);
                  ref.invalidate(adminDashboardProvider);
                },
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Archiver la saison'),
              ),
            ],
            const SizedBox(height: 12),
            ...dashboard.seasons.map(
              (season) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(season.name),
                trailing: Chip(label: Text(season.status)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateSeasonDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final now = DateTime.now();
    final controller = TextEditingController(
      text: '${now.year}-${now.year + 1}',
    );
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nouvelle saison'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Nom',
                  hintText: '2026-2027',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await ref
                      .read(adminRepositoryProvider)
                      .createSeason(controller.text);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  ref.invalidate(adminDashboardProvider);
                } catch (exception) {
                  if (dialogContext.mounted) {
                    setDialogState(() => error = exception.toString());
                  }
                }
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }
}

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard({
    required this.profile,
    required this.openSeasonId,
  });

  final AdminProfileItem profile;
  final String? openSeasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.read(adminRepositoryProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.fullName.isEmpty
                            ? profile.email
                            : profile.fullName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(profile.email),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Supprimer définitivement',
                  color: Theme.of(context).colorScheme.error,
                  icon: const Icon(Icons.delete_forever_outlined),
                  onPressed: () => _deletePermanently(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: profile.role,
              decoration: const InputDecoration(labelText: 'Rôle'),
              items: const [
                DropdownMenuItem(
                  value: 'pronostiqueur',
                  child: Text('Pronostiqueur'),
                ),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
                DropdownMenuItem(
                  value: 'moderateur',
                  child: Text('Modérateur'),
                ),
              ],
              onChanged: (value) async {
                if (value == null || value == profile.role) return;
                await repository.updateProfileRole(profile.id, value);
                ref.invalidate(adminDashboardProvider);
              },
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Compte actif'),
              value: profile.status == 'active',
              onChanged: (value) async {
                await repository.updateProfileStatus(
                  profile.id,
                  value ? 'active' : 'archived',
                );
                ref.invalidate(adminDashboardProvider);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Gardien'),
              value: profile.isGoalkeeper,
              onChanged: (value) async {
                await repository.updateGoalkeeper(profile.id, value);
                ref.invalidate(adminDashboardProvider);
              },
            ),
            if (openSeasonId != null)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dans l’effectif de la saison ouverte'),
                value: profile.inOpenSeason,
                onChanged: (value) async {
                  await repository.setSeasonMembership(
                    seasonId: openSeasonId!,
                    profile: profile,
                    selected: value == true,
                  );
                  ref.invalidate(adminDashboardProvider);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deletePermanently(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmationController = TextEditingController();
    final expected = profile.email;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Suppression définitive'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cette action supprime le compte Auth et toutes les données liées. '
              'Elle est irréversible.',
            ),
            const SizedBox(height: 12),
            Text('Saisissez « $expected » pour confirmer.'),
            const SizedBox(height: 8),
            TextField(
              controller: confirmationController,
              decoration:
                  const InputDecoration(labelText: 'Email de confirmation'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              confirmationController.text.trim().toLowerCase() ==
                  expected.toLowerCase(),
            ),
            child: const Text('Supprimer définitivement'),
          ),
        ],
      ),
    );
    confirmationController.dispose();
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(adminRepositoryProvider).permanentlyDeleteUser(profile.id);
      ref.invalidate(adminDashboardProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compte supprimé définitivement.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
