import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/home/data/home_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final dashboardAsync = ref.watch(homeDashboardProvider);
    final isModerator = authState.profile?.role == AuthRole.moderateur;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AS Grinta'),
        actions: [
          if (isModerator)
            IconButton(
              tooltip: 'Administration',
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => context.go('/admin'),
            ),
          IconButton(
            tooltip: 'Profil',
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.go('/profile'),
          ),
          IconButton(
            tooltip: 'Déconnexion',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).signOut();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(homeDashboardProvider);
          await ref.read(homeDashboardProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              authState.profile?.fullName.isNotEmpty == true
                  ? 'Bonjour ${authState.profile!.fullName}'
                  : 'Bienvenue',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text('Rôle : ${authState.profile?.role.label ?? 'inconnu'}'),
            const SizedBox(height: 20),
            dashboardAsync.when(
              loading: () => const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        error.toString(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => ref.invalidate(homeDashboardProvider),
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (dashboard) => Column(
                children: [
                  _NextMatchCard(dashboard: dashboard),
                  if (dashboard.pendingPredictions > 0) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.tips_and_updates_outlined),
                        title: Text(
                          '${dashboard.pendingPredictions} pronostic(s) à saisir',
                        ),
                        subtitle: const Text(
                          'La fenêtre est ouverte et se ferme 12 h avant le match.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.go('/predictions'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _HomeAction(
                  icon: Icons.calendar_month_outlined,
                  label: 'Matchs',
                  onTap: () => context.go('/matches'),
                ),
                _HomeAction(
                  icon: Icons.tips_and_updates_outlined,
                  label: 'Pronostics',
                  onTap: () => context.go('/predictions'),
                ),
                _HomeAction(
                  icon: Icons.bar_chart_outlined,
                  label: 'Statistiques',
                  onTap: () => context.go('/statistics'),
                ),
                _HomeAction(
                  icon: isModerator
                      ? Icons.admin_panel_settings_outlined
                      : Icons.person_outline,
                  label: isModerator ? 'Administration' : 'Profil',
                  onTap: () => context.go(isModerator ? '/admin' : '/profile'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NextMatchCard extends StatelessWidget {
  const _NextMatchCard({required this.dashboard});

  final HomeDashboardData dashboard;

  @override
  Widget build(BuildContext context) {
    if (dashboard.nextMatchId == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Text('Aucun prochain match programmé.'),
        ),
      );
    }

    final isLive = dashboard.nextMatchStatus == 'en_cours';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isLive ? 'Match en direct' : 'Prochain match',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (isLive) const Chip(label: Text('LIVE')),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'AS Grinta - ${dashboard.nextOpponent ?? 'Adversaire'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (dashboard.nextKickoffAt != null) ...[
              const SizedBox(height: 6),
              Text(
                dashboard.nextKickoffAt!
                    .toLocal()
                    .toString()
                    .split('.')
                    .first,
              ),
            ],
            if (isLive) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () =>
                      context.go('/live/${dashboard.nextMatchId}'),
                  icon: const Icon(Icons.sensors),
                  label: const Text('Ouvrir le Live'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomeAction extends StatelessWidget {
  const _HomeAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 34),
            const SizedBox(height: 10),
            Text(label, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
