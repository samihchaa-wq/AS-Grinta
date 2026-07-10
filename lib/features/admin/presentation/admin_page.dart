import 'package:as_grinta/features/admin/data/admin_repository.dart';
import 'package:as_grinta/features/players/data/players_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AdminPage extends ConsumerWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(adminDashboardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Administration')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(adminDashboardProvider);
          await ref.read(adminDashboardProvider.future);
        },
        child: dashboardAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Impossible de charger l’administration : $error'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(adminDashboardProvider),
                child: const Text('Réessayer'),
              ),
            ],
          ),
          data: (dashboard) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _QuickActions(onInvite: () => _invitePlayer(context, ref)),
              const SizedBox(height: 20),
              _SeasonCard(dashboard: dashboard),
              const SizedBox(height: 20),
              Text(
                'Comptes et effectif',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              if (dashboard.profiles.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('Aucun compte disponible.'),
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

  Future<void> _invitePlayer(BuildContext context, WidgetRef ref) async {
    final email = TextEditingController();
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
        builder: (context, setState) => AlertDialog(
          title: const Text('Inviter un joueur'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nickname,
                  decoration: const InputDecoration(
                    labelText: 'Surnom (facultatif)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: firstName,
                  decoration: const InputDecoration(labelText: 'Prénom'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: lastName,
                  decoration: const InputDecoration(labelText: 'Nom'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Gardien'),
                  value: isGoalkeeper,
                  onChanged: saving
                      ? null
                      : (value) => setState(() => isGoalkeeper = value),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
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
                      final cleanEmail = email.text.trim();
                      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                              .hasMatch(cleanEmail) ||
                          firstName.text.trim().isEmpty ||
                          lastName.text.trim().isEmpty) {
                        setState(
                          () => error =
                              'Un email valide, le prénom et le nom sont obligatoires.',
                        );
                        return;
                      }
                      setState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await ref.read(adminRepositoryProvider).inviteAccount(
                              email: cleanEmail,
                              firstName: firstName.text,
                              lastName: lastName.text,
                              surnom: nickname.text,
                            );
                        final token = await ref
                            .read(playersRepositoryProvider)
                            .createPlayerInvitation(
                              firstName: firstName.text,
                              lastName: lastName.text,
                              surnom: nickname.text,
                              isGoalkeeper: isGoalkeeper,
                            );
                        final link = Uri.base.resolve('claim?token=$token').toString();
                        ref.invalidate(playersListProvider);
                        ref.invalidate(adminDashboardProvider);
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        await showDialog<void>(
                          context: context,
                          builder: (linkContext) => AlertDialog(
                            title: const Text('Invitation envoyée'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Un email d’activation a été envoyé à $cleanEmail.',
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Après activation, le joueur doit ouvrir ce lien pour rattacher sa fiche :',
                                ),
                                const SizedBox(height: 8),
                                SelectableText(link),
                              ],
                            ),
                            actions: [
                              TextButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: link),
                                  );
                                },
                                icon: const Icon(Icons.copy),
                                label: const Text('Copier le lien'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(linkContext),
                                child: const Text('Fermer'),
                              ),
                            ],
                          ),
                        );
                      } catch (exception) {
                        if (!dialogContext.mounted) return;
                        setState(() {
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
                  : const Text('Envoyer l’invitation'),
            ),
          ],
        ),
      ),
    );

    email.dispose();
    firstName.dispose();
    lastName.dispose();
    nickname.dispose();
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onInvite});

  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gestion rapide',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () => context.push('/matches'),
                  icon: const Icon(Icons.sports_soccer_outlined),
                  label: const Text('Matchs'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.push('/players'),
                  icon: const Icon(Icons.groups_outlined),
                  label: const Text('Joueurs'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.push('/statistics'),
                  icon: const Icon(Icons.bar_chart_outlined),
                  label: const Text('Statistiques'),
                ),
                OutlinedButton.icon(
                  onPressed: onInvite,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Inviter'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SeasonCard extends ConsumerWidget {
  const _SeasonCard({required this.dashboard});

  final AdminDashboardData dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openSeasons = dashboard.seasons.where((item) => item.status == 'open');
    final openSeason = openSeasons.isEmpty ? null : openSeasons.first;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saison', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            if (openSeason == null)
              FilledButton.icon(
                onPressed: () => _createSeason(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Créer une saison'),
              )
            else ...[
              Text('Saison ouverte : ${openSeason.name}'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await ref
                      .read(adminRepositoryProvider)
                      .archiveSeason(openSeason.id);
                  ref.invalidate(adminDashboardProvider);
                },
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Archiver'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _createSeason(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final controller = TextEditingController(
      text: '${now.year}-${now.year + 1}',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nouvelle saison'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '2026-2027'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    await ref.read(adminRepositoryProvider).createSeason(name);
    ref.invalidate(adminDashboardProvider);
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
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              profile.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (profile.email.trim().isNotEmpty) Text(profile.email),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: profile.role,
              decoration: const InputDecoration(labelText: 'Rôle'),
              items: const [
                DropdownMenuItem(
                  value: 'pronostiqueur',
                  child: Text('Joueur'),
                ),
                DropdownMenuItem(
                  value: 'moderateur',
                  child: Text('Modérateur'),
                ),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
              ],
              onChanged: (value) async {
                if (value == null || value == profile.role) return;
                await repository.updateProfileRole(profile.id, value);
                ref.invalidate(adminDashboardProvider);
              },
            ),
            const SizedBox(height: 8),
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dans la saison ouverte'),
                value: profile.inOpenSeason,
                onChanged: (value) async {
                  await repository.setSeasonMembership(
                    seasonId: openSeasonId!,
                    profile: profile,
                    selected: value,
                  );
                  ref.invalidate(adminDashboardProvider);
                },
              ),
          ],
        ),
      ),
    );
  }
}
