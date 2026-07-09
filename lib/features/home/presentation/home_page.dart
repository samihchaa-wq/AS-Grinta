import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/home/data/home_repository.dart';
import 'package:as_grinta/features/predictions/presentation/predictions_controller.dart';
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
    final displayName = authState.profile?.displayName.trim() ?? '';
    final greeting = displayName.isNotEmpty ? displayName : 'Grinta';

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
                      name: greeting,
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
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      dashboardAsync.when(
                        loading: () => const _LoadingHero(),
                        error: (error, _) => _ErrorCard(
                          message: error.toString(),
                          onRetry: () => ref.invalidate(homeDashboardProvider),
                        ),
                        data: (dashboard) => _NextMatchHero(
                          dashboard: dashboard,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Pronostic inline pour le prochain match
                      _InlinePrediction(isModerator: isModerator),
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

// ─── Header ──────────────────────────────────────────────────────────────────

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

// ─── Prochain match ───────────────────────────────────────────────────────────

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
                    const Icon(
                      Icons.arrow_outward_rounded,
                      color: Colors.white54,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (!hasMatch)
                  Text(
                    'Aucun match programmé',
                    style: Theme.of(context).textTheme.headlineMedium,
                  )
                else ...[
                  // Noms des équipes + score sur une seule ligne
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'AS GRINTA  vs  ${dashboard.nextOpponent ?? 'Adversaire'}',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (dashboard.nextKickoffAt != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          size: 16,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          AppFormats.dateTime(dashboard.nextKickoffAt!),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.white70,
                              ),
                        ),
                      ],
                    ),
                  ],
                  if (isLive) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => context
                          .go('/live/${dashboard.nextMatchId}'),
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

// ─── Widget inline pronostic ─────────────────────────────────────────────────

class _InlinePrediction extends ConsumerStatefulWidget {
  const _InlinePrediction({required this.isModerator});
  final bool isModerator;

  @override
  ConsumerState<_InlinePrediction> createState() => _InlinePredictionState();
}

class _InlinePredictionState extends ConsumerState<_InlinePrediction> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(predictionsControllerProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Les modérateurs gèrent les matchs, pas les pronostics
    if (widget.isModerator) return const SizedBox.shrink();

    final state = ref.watch(predictionsControllerProvider);

    if (state.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (state.items.isEmpty) return const SizedBox.shrink();

    final item = state.items.first;
    final isSaving = state.savingMatchId == item.matchId;
    final controller = ref.read(predictionsControllerProvider.notifier);

    // Si la fenêtre n'est pas encore ouverte ou est fermée, affiche juste un
    // message compact.
    if (item.isBeforeWindow) {
      return _StatusChip(
        icon: Icons.lock_clock_outlined,
        label: 'Pronostics ouverts à partir du '
            '${AppFormats.date(item.opensAt)}',
      );
    }

    if (item.isClosed) {
      return _StatusChip(
        icon: Icons.lock_outline,
        label: item.isFilled
            ? 'Pronostic enregistré · Fenêtre fermée'
            : 'Fenêtre de pronostic fermée',
      );
    }

    // Fenêtre ouverte → afficher le formulaire inline
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.outline),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.bolt_rounded,
                    color: AppTheme.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ton pronostic',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Ferme 10 min avant le coup d\'envoi',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF91A69B),
                          ),
                    ),
                  ],
                ),
              ),
              if (item.isFilled)
                Chip(
                  label: const Text('Enregistré'),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Scores sur une seule ligne, sans overflow
          Row(
            children: [
              Expanded(
                child: _ScoreCol(
                  label: 'AS Grinta',
                  value: item.scoreGrinta,
                  enabled: item.canEdit && !isSaving,
                  onMinus: () => controller.changeScore(
                    matchId: item.matchId,
                    grinta: true,
                    delta: -1,
                  ),
                  onPlus: () => controller.changeScore(
                    matchId: item.matchId,
                    grinta: true,
                    delta: 1,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '–',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(color: Colors.white38),
                ),
              ),
              Expanded(
                child: _ScoreCol(
                  label: item.opponentName,
                  value: item.scoreOpponent,
                  enabled: item.canEdit && !isSaving,
                  onMinus: () => controller.changeScore(
                    matchId: item.matchId,
                    grinta: false,
                    delta: -1,
                  ),
                  onPlus: () => controller.changeScore(
                    matchId: item.matchId,
                    grinta: false,
                    delta: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: !item.canEdit || isSaving
                  ? null
                  : () => controller.save(item.matchId),
              icon: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Enregistrer'),
            ),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 8),
            Text(
              state.error!,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.error, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScoreCol extends StatelessWidget {
  const _ScoreCol({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final int value;
  final bool enabled;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: enabled ? onMinus : null,
              icon: const Icon(Icons.remove_circle_outline),
              visualDensity: VisualDensity.compact,
            ),
            Text(
              '$value',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            IconButton(
              onPressed: enabled ? onPlus : null,
              icon: const Icon(Icons.add_circle_outline),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF91A69B)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF91A69B),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chargement / Erreur ──────────────────────────────────────────────────────

class _LoadingHero extends StatelessWidget {
  const _LoadingHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
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
