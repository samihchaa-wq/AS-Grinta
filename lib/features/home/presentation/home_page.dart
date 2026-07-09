import 'package:as_grinta/core/theme/app_theme.dart';
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
    final firstName = authState.profile?.firstName.trim();

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B1A13), AppTheme.background],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(homeDashboardProvider);
              await ref.read(homeDashboardProvider.future);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: _Header(
                      name:
                          firstName?.isNotEmpty == true ? firstName! : 'Grinta',
                      role: authState.profile?.role.label ?? 'Membre',
                      isModerator: isModerator,
                      onAdmin: () => context.go('/admin'),
                      onProfile: () => context.go('/profile'),
                      onLogout: () =>
                          ref.read(authControllerProvider.notifier).signOut(),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      dashboardAsync.when(
                        loading: () => const _LoadingHero(),
                        error: (error, _) => _ErrorCard(
                          message: error.toString(),
                          onRetry: () => ref.invalidate(homeDashboardProvider),
                        ),
                        data: (dashboard) => Column(
                          children: [
                            _NextMatchHero(dashboard: dashboard),
                            if (dashboard.pendingPredictions > 0) ...[
                              const SizedBox(height: 14),
                              _PredictionBanner(
                                count: dashboard.pendingPredictions,
                                onTap: () => context.go('/predictions'),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Text(
                            'Accès rapide',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Spacer(),
                          Text(
                            'SAISON 2026',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      GridView.count(
                        crossAxisCount: 2,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 1.1,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _HomeAction(
                            icon: Icons.calendar_month_rounded,
                            label: 'Matchs',
                            subtitle: 'Calendrier & résultats',
                            onTap: () => context.go('/matches'),
                          ),
                          _HomeAction(
                            icon: Icons.bolt_rounded,
                            label: 'Pronostics',
                            subtitle: 'Joue avant le coup d’envoi',
                            onTap: () => context.go('/predictions'),
                          ),
                          _HomeAction(
                            icon: Icons.insights_rounded,
                            label: 'Statistiques',
                            subtitle: 'Forme & performances',
                            onTap: () => context.go('/statistics'),
                          ),
                          _HomeAction(
                            icon: isModerator
                                ? Icons.shield_rounded
                                : Icons.person_rounded,
                            label: isModerator ? 'Gestion' : 'Profil',
                            subtitle: isModerator
                                ? 'Équipe & administration'
                                : 'Compte & préférences',
                            onTap: () =>
                                context.go(isModerator ? '/admin' : '/profile'),
                          ),
                        ],
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.role,
    required this.isModerator,
    required this.onAdmin,
    required this.onProfile,
    required this.onLogout,
  });

  final String name;
  final String role;
  final bool isModerator;
  final VoidCallback onAdmin;
  final VoidCallback onProfile;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [AppTheme.primary, Color(0xFF0FAE60)],
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.22),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(Icons.sports_soccer_rounded, color: Colors.black),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Salut $name',
                style: Theme.of(context).textTheme.headlineMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                role.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
              ),
            ],
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Menu',
          icon: const Icon(Icons.more_horiz_rounded),
          onSelected: (value) async {
            if (value == 'admin') onAdmin();
            if (value == 'profile') onProfile();
            if (value == 'logout') await onLogout();
          },
          itemBuilder: (_) => [
            if (isModerator)
              const PopupMenuItem(
                value: 'admin',
                child: Text('Administration'),
              ),
            const PopupMenuItem(value: 'profile', child: Text('Profil')),
            const PopupMenuItem(value: 'logout', child: Text('Déconnexion')),
          ],
        ),
      ],
    );
  }
}

class _NextMatchHero extends StatelessWidget {
  const _NextMatchHero({required this.dashboard});

  final HomeDashboardData dashboard;

  @override
  Widget build(BuildContext context) {
    final hasMatch = dashboard.nextMatchId != null;
    final isLive = dashboard.nextMatchStatus == 'en_cours';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF17392A), Color(0xFF0D2018)],
        ),
        border: Border.all(color: const Color(0xFF2D5B45)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 36,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -34,
            top: -28,
            child: Icon(
              Icons.sports_soccer_rounded,
              size: 170,
              color: Colors.white.withValues(alpha: 0.035),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: isLive
                            ? const Color(0xFFFF5D5D).withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isLive ? '● EN DIRECT' : 'PROCHAIN MATCH',
                        style: TextStyle(
                          color: isLive
                              ? const Color(0xFFFF7B7B)
                              : AppTheme.primary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_outward_rounded,
                        color: Colors.white54),
                  ],
                ),
                const SizedBox(height: 26),
                if (!hasMatch)
                  Text(
                    'Aucun match programmé',
                    style: Theme.of(context).textTheme.headlineMedium,
                  )
                else ...[
                  Text(
                    'AS GRINTA',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          fontSize: 36,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'vs ${dashboard.nextOpponent ?? 'Adversaire'}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: const Color(0xFFD2E1D8),
                        ),
                  ),
                  if (dashboard.nextKickoffAt != null) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          dashboard.nextKickoffAt!
                              .toLocal()
                              .toString()
                              .split('.')
                              .first,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ],
                  if (isLive) ...[
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: () =>
                          context.go('/live/${dashboard.nextMatchId}'),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Ouvrir le live'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PredictionBanner extends StatelessWidget {
  const _PredictionBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.bolt_rounded, color: AppTheme.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count pronostic${count > 1 ? 's' : ''} à jouer',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'La fenêtre ferme 12 h avant le match.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeAction extends StatelessWidget {
  const _HomeAction({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: AppTheme.primary),
              ),
              const Spacer(),
              Text(label, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF91A69B),
                      height: 1.25,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingHero extends StatelessWidget {
  const _LoadingHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 245,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppTheme.outline),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.error_outline_rounded, size: 38),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}
