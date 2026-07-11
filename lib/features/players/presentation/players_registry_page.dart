import 'package:as_grinta/features/admin/data/admin_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Registre des joueurs : chaque profil est soit « pronostiqueur »
/// (il participe uniquement aux pronos), soit « pronostiqueur + joueur »
/// (il apparaît en plus sur la feuille de match, où l'admin saisit
/// présence, buts, passes, HDM, fautes provoquant un penalty…).
class PlayersRegistryPage extends ConsumerWidget {
  const PlayersRegistryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(adminDashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registre des joueurs'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () => ref.invalidate(adminDashboardProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: dashboardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 52),
                const SizedBox(height: 14),
                const Text(
                  'Registre temporairement indisponible.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(adminDashboardProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualiser'),
                ),
              ],
            ),
          ),
        ),
        data: (dashboard) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(adminDashboardProvider);
            await ref.read(adminDashboardProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              const Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Pronostiqueur ou pronostiqueur + joueur'),
                  subtitle: Text(
                    'Tous les profils pronostiquent. Ceux marqués '
                    '« joueur » apparaissent en plus sur la feuille de '
                    'match : présence, buts, passes décisives, homme du '
                    'match, fautes provoquant un penalty…',
                  ),
                ),
              ),
              if (dashboard.openSeasonId == null) ...[
                const SizedBox(height: 12),
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.warning_amber_rounded),
                    title: Text('Aucune saison ouverte'),
                    subtitle: Text(
                      'Ouvre une saison dans Administration pour pouvoir '
                      'définir les joueurs.',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (dashboard.profiles.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('Aucun profil enregistré.'),
                  ),
                )
              else
                ...dashboard.profiles.map(
                  (profile) => _RegistryCard(
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

class _RegistryCard extends ConsumerWidget {
  const _RegistryCard({required this.profile, required this.openSeasonId});

  final AdminProfileItem profile;
  final String? openSeasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.read(adminRepositoryProvider);
    final isPlayer = profile.inOpenSeason;

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
        ref.invalidate(adminDashboardProvider);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('L’opération n’a pas pu être effectuée.'),
            ),
          );
        }
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Icon(
                    isPlayer
                        ? (profile.isGoalkeeper
                            ? Icons.sports_handball
                            : Icons.sports_soccer)
                        : Icons.bolt_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        [
                          if (profile.username.trim().isNotEmpty)
                            profile.username,
                          isPlayer
                              ? 'Pronostiqueur + joueur'
                              : 'Pronostiqueur',
                          if (profile.isGoalkeeper) 'Gardien',
                          if (profile.status == 'pending')
                            'En attente de validation',
                          if (profile.status == 'archived') 'Archivé',
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Joueur (feuille de match)'),
              value: isPlayer,
              onChanged: openSeasonId == null
                  ? null
                  : (value) => run(
                        () => repository.setSeasonMembership(
                          seasonId: openSeasonId!,
                          profile: profile,
                          selected: value,
                        ),
                      ),
            ),
            if (isPlayer)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Gardien'),
                value: profile.isGoalkeeper,
                onChanged: (value) =>
                    run(() => repository.updateGoalkeeper(profile.id, value)),
              ),
          ],
        ),
      ),
    );
  }
}
