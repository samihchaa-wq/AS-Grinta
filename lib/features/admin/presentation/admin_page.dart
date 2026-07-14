import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/admin/data/admin_repository.dart';
import 'package:as_grinta/features/admin/presentation/admin_profile_policy.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/matches/presentation/match_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

part 'admin_season_section.dart';
part 'admin_profiles_section.dart';

/// Lien public d'auto-inscription à partager dans la conversation du club.
const _registerLink = 'https://samihchaa-wq.github.io/AS-Grinta/auth/register';

class AdminPage extends ConsumerWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(adminDashboardProvider);

    return Scaffold(
      appBar: GrintaAppBar(title: const SizedBox.shrink()),
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
          data: (dashboard) {
            final groups = groupAdminProfiles(dashboard.profiles);

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _SeasonCard(dashboard: dashboard),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Text('👑', style: TextStyle(fontSize: 22)),
                    title: const Text('Ajouter un match'),
                    subtitle: const Text(
                      'Créer un nouveau match dans le calendrier.',
                    ),
                    trailing: const Icon(Icons.add_circle_outline),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MatchFormPage(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Text('👑', style: TextStyle(fontSize: 22)),
                    title: const Text('Gérer les matchs'),
                    subtitle: const Text(
                      'Créer, modifier, saisir les statistiques ou supprimer.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/admin/matches'),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Pronostiqueurs',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Chacun crée son compte via le lien. Tu valides ensuite les '
                  'nouveaux comptes ci-dessous. (L’effectif des joueurs se '
                  'gère dans « Registre des joueurs ».)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: () async {
                      await Clipboard.setData(
                        const ClipboardData(text: _registerLink),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Lien d’inscription copié — partage-le sur '
                              'WhatsApp.',
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.link, size: 18),
                    label: const Text('Copier le lien d’inscription'),
                  ),
                ),
                const SizedBox(height: 20),
                if (dashboard.profiles.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('Aucun compte pour l’instant.'),
                    ),
                  )
                else ...[
                  _ProfilesSection(
                    title: 'En attente de validation',
                    profiles: groups.pending,
                    emptyMessage: 'Aucun compte en attente.',
                    icon: Icons.hourglass_top_rounded,
                  ),
                  const SizedBox(height: 20),
                  _ProfilesSection(
                    title: 'Validés',
                    profiles: groups.validated,
                    emptyMessage: 'Aucun compte validé.',
                    icon: Icons.verified_outlined,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
