import 'package:as_grinta/core/config/app_config.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/features/admin/data/admin_repository.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/players/data/roster_repository.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/auth/presentation/sign_out_confirmation.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final isAdminView = ref.watch(isAdminViewProvider);
    final sportsEnabled = ref.watch(sportsManagementEnabledProvider);

    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Paramètres')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // La carte du compte remplace l'ancienne ligne « Profil » : on voit
          // tout de suite avec quel compte on est connecté.
          _ProfileHeaderCard(
            profile: authState.profile,
            onTap: () => context.push('/profile'),
          ),
          // Les notifications s'ouvrent depuis la cloche de l'en-tête.
          if (sportsEnabled) ...[
            const _SectionLabel('Mon compte'),
            _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: Icons.event_busy_outlined,
                  title: 'Indisponibilité',
                  onTap: () => context.push('/unavailability'),
                ),
                _SettingsTile(
                  icon: Icons.format_list_numbered_rounded,
                  title: 'Liste d’attente',
                  onTap: () => context.push(
                    isAdminView ? '/admin/waitlist' : '/waitlist',
                  ),
                ),
              ],
            ),
          ],
          if (isAdminView) ...[
            const _SectionLabel('Club · admin'),
            _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: Icons.groups_outlined,
                  title: 'Effectif',
                  onTap: () => context.push('/admin'),
                ),
                _SettingsTile(
                  icon: Icons.stadium_outlined,
                  title: 'Équipes & stades',
                  onTap: () async {
                    await context.push('/admin/stadiums');
                    if (!context.mounted) return;
                    // Rafraîchir les cartes de matchs après une modification.
                    try {
                      await ref.read(matchesControllerProvider.notifier).load(
                            allSeasons: true,
                            forceRefresh: true,
                          );
                    } catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(humanizeError(error))),
                      );
                    }
                  },
                ),
                const _ClubSeasonTile(),
              ],
            ),
          ],
          const SizedBox(height: 20),
          // Aussi proposé dans le Profil : c'est ici qu'on le cherche d'abord.
          Center(
            child: TextButton.icon(
              onPressed: authState.isBusy
                  ? null
                  : () => confirmAndSignOut(context, ref),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Se déconnecter'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'AS Grinta • version ${AppConfig.version}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Action de saison directement dans Paramètres, sans écran Réglages.
class _ClubSeasonTile extends ConsumerWidget {
  const _ClubSeasonTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(adminDashboardProvider);
    return dashboard.when(
      loading: () => const ListTile(
        leading: Icon(Icons.flag_outlined),
        title: Text('Saison'),
        subtitle: Text('Chargement…'),
      ),
      error: (_, __) => ListTile(
        leading: const Icon(Icons.refresh),
        title: const Text('Saison indisponible'),
        subtitle: const Text('Appuyer pour réessayer'),
        onTap: () => ref.invalidate(adminDashboardProvider),
      ),
      data: (data) {
        AdminSeasonItem? current;
        for (final season in data.seasons) {
          if (season.status == 'open') {
            current = season;
            break;
          }
        }
        final openSeason = current;
        if (openSeason == null) {
          return ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: const Text('Créer une saison'),
            onTap: () => _createSeason(context, ref),
          );
        }
        return ListTile(
          leading: Icon(Icons.flag_outlined, color: AppTheme.error),
          title: Text(
            'Finir la saison',
            style: TextStyle(color: AppTheme.error),
          ),
          subtitle: Text('Saison ${openSeason.name}'),
          onTap: () => _finishSeason(context, ref, openSeason),
        );
      },
    );
  }

  Future<void> _finishSeason(
    BuildContext context,
    WidgetRef ref,
    AdminSeasonItem season,
  ) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Finir la saison ?'),
            content: Text(
              'La saison « ${season.name} » sera archivée immédiatement '
              'et le classement final figé. C’est définitif. '
              'Tu pourras ensuite créer une nouvelle saison.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirmer'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(adminRepositoryProvider).setSeasonStatus(
            season.id,
            'archived',
          );
      ref.invalidate(adminDashboardProvider);
      ref.invalidate(openSeasonIdProvider);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(humanizeError(error))),
      );
    }
  }

  Future<void> _createSeason(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    var enteredName = '${now.year}-${now.year + 1}';
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nouvelle saison'),
        content: TextFormField(
          initialValue: enteredName,
          onChanged: (value) => enteredName = value,
          decoration: const InputDecoration(hintText: '2026-2027'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, enteredName),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    try {
      await ref.read(adminRepositoryProvider).createSeason(name);
      ref.invalidate(adminDashboardProvider);
      ref.invalidate(openSeasonIdProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saison « ${name.trim()} » ouverte.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(humanizeError(error))),
      );
    }
  }
}

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({required this.profile, required this.onTap});

  final AuthProfile? profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final profile = this.profile;
    final fullName = profile?.fullName.trim() ?? '';
    final username = profile?.username?.trim() ?? '';
    final details = [
      if (username.isNotEmpty) '@$username',
      if (profile != null) profile.role.label,
    ].join(' · ');

    // Lue comme un seul bouton : nom, identifiant et rôle, puis l'action.
    return Card(
      clipBehavior: Clip.antiAlias,
      child: MergeSemantics(
        child: Semantics(
          button: true,
          hint: 'Ouvrir le profil',
          child: InkWell(
            onTap: onTap,
            child: Padding(
              // Même retrait à droite que les lignes (ListTile), pour que les
              // chevrons de la page restent alignés.
              padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 24, 14),
              child: Row(
                children: [
                  // Les initiales répéteraient le nom lu juste après.
                  ExcludeSemantics(
                    child: PlayerAvatar(
                      photoUrl: profile?.photoUrl,
                      name: profile?.displayName ?? '',
                      lastName: profile?.lastName,
                      size: 56,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName.isEmpty ? 'Mon profil' : fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (details.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            details,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppTheme.textFaint),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Semantics(
        header: true,
        child: Text(
          label.toUpperCase(),
          semanticsLabel: label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppTheme.textFaint,
                fontWeight: FontWeight.w400,
                letterSpacing: 1.2,
              ),
        ),
      ),
    );
  }
}

/// Une seule carte par groupe, lignes séparées par un filet fin.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < children.length; index += 1) ...[
            if (index > 0) const Divider(height: 1, indent: 56),
            children[index],
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.primaryBright),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
