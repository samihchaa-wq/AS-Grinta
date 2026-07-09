import 'package:as_grinta/features/admin/data/admin_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          loading: () => const ListView(
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
              Text(
                'Comptes et effectif',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
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
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nouvelle saison'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nom',
            hintText: '2026-2027',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              await ref.read(adminRepositoryProvider).createSeason(controller.text);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              ref.invalidate(adminDashboardProvider);
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
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
            Text(
              profile.fullName.isEmpty ? profile.email : profile.fullName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(profile.email),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: profile.role,
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
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
