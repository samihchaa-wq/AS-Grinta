import 'package:as_grinta/core/config/app_config.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/admin/presentation/opponent_stadium_library_page.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/auth/presentation/sign_out_confirmation.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final isRealAdmin = ref.watch(isRealAdminProvider);
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
          const _SectionLabel('Mon compte'),
          _SettingsGroup(
            children: [
              _SettingsTile(
                icon: Icons.notifications_none_outlined,
                title: 'Notifications',
                onTap: () => context.push('/notifications'),
              ),
              if (sportsEnabled) ...[
                _SettingsTile(
                  icon: Icons.event_busy_outlined,
                  title: 'Indisponibilité',
                  onTap: () => context.push('/unavailability'),
                ),
                _SettingsTile(
                  icon: Icons.format_list_numbered_rounded,
                  title: 'Liste d’attente',
                  onTap: () => context.push(
                    isRealAdmin ? '/admin/waitlist' : '/waitlist',
                  ),
                ),
              ],
            ],
          ),
          if (isRealAdmin) ...[
            const _SectionLabel('Club · admin'),
            _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: Icons.stadium_outlined,
                  title: 'Équipes & stades',
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const OpponentStadiumLibraryPage(),
                      ),
                    );
                    if (!context.mounted) return;
                    await ref.read(matchesControllerProvider.notifier).load(
                          allSeasons: true,
                          forceRefresh: true,
                        );
                  },
                ),
                _SettingsTile(
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'Administration',
                  onTap: () => context.push('/admin'),
                ),
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
              'AS La Grinta • version ${AppConfig.version}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
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
