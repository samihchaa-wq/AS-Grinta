import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/features/admin/data/admin_repository.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Lien public d'auto-inscription à partager dans la conversation du club.
const _registerLink = 'https://samihchaa-wq.github.io/AS-Grinta/auth/register';

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
          data: (dashboard) {
            final pendingProfiles = dashboard.profiles
                .where((profile) => profile.status == 'pending')
                .toList();
            final validatedProfiles = dashboard.profiles
                .where((profile) => profile.status != 'pending')
                .toList();

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _SeasonCard(dashboard: dashboard),
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
                    profiles: pendingProfiles,
                    emptyMessage: 'Aucun compte en attente.',
                    icon: Icons.hourglass_top_rounded,
                  ),
                  const SizedBox(height: 20),
                  _ProfilesSection(
                    title: 'Validés',
                    profiles: validatedProfiles,
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

class _SeasonCard extends ConsumerWidget {
  const _SeasonCard({required this.dashboard});

  final AdminDashboardData dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openSeasons = dashboard.seasons.where(
      (item) => item.status == 'open',
    );
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  openSeason.predictionsLocked
                      ? 'Paris de saison fermés'
                      : 'Paris de saison ouverts',
                ),
                subtitle: Text(
                  openSeason.predictionsLocked
                      ? 'Fermés : les pronostics de chacun sont visibles par '
                            'tous et figés. Le classement de saison tourne.'
                      : 'Ouverts : chacun parie en secret. Ferme les paris '
                            'pour les révéler à tous et lancer le classement.',
                ),
                value: openSeason.predictionsLocked,
                onChanged: (lock) async {
                  if (lock) {
                    final confirmed =
                        await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Fermer les paris ?'),
                            content: const Text(
                              'Les pronostics de saison de tout le monde '
                              'deviendront visibles et ne pourront plus être '
                              'modifiés. Le classement de saison démarre.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('Annuler'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: const Text('Fermer'),
                              ),
                            ],
                          ),
                        ) ??
                        false;
                    if (!confirmed) return;
                  }
                  try {
                    await ref
                        .read(adminRepositoryProvider)
                        .setSeasonPredictionsLock(
                          seasonId: openSeason.id,
                          locked: lock,
                        );
                    ref.invalidate(adminDashboardProvider);
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(humanizeError(error))),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => _changeStatus(
                    context,
                    ref,
                    openSeason,
                    'archived',
                    title: 'Finir la saison ?',
                    message:
                        'La saison « ${openSeason.name} » sera archivée '
                        'immédiatement et le classement final figé. '
                        'C’est définitif. Tu pourras ensuite créer une '
                        'nouvelle saison.',
                  ),
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Finir la saison'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _changeStatus(
    BuildContext context,
    WidgetRef ref,
    AdminSeasonItem season,
    String status, {
    required String title,
    required String message,
  }) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
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
    if (!confirmed) return;
    try {
      await ref
          .read(adminRepositoryProvider)
          .setSeasonStatus(season.id, status);
      ref.invalidate(adminDashboardProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    }
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
    if (name == null || name.trim().isEmpty) return;
    try {
      await ref.read(adminRepositoryProvider).createSeason(name);
      ref.invalidate(adminDashboardProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saison « ${name.trim()} » ouverte. Ajoute maintenant ton '
              'effectif.',
            ),
          ),
        );
        // Enchaîne sur la saisie de l'effectif (la liste des joueurs).
        context.push('/players');
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    }
  }
}

class _ProfilesSection extends StatelessWidget {
  const _ProfilesSection({
    required this.title,
    required this.profiles,
    required this.emptyMessage,
    required this.icon,
  });

  final String title;
  final List<AdminProfileItem> profiles;
  final String emptyMessage;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text('${profiles.length}'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (profiles.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(emptyMessage)),
                ],
              ),
            ),
          )
        else
          ...profiles.map((profile) => _ProfileCard(profile: profile)),
      ],
    );
  }
}

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard({required this.profile});

  final AdminProfileItem profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.read(adminRepositoryProvider);
    final currentUserId = ref.watch(authControllerProvider).profile?.id;
    final isSelf = currentUserId != null && currentUserId == profile.id;
    final isPending = profile.status == 'pending';

    Future<void> run(Future<void> Function() action, {String? success}) async {
      try {
        await action();
        ref.invalidate(adminDashboardProvider);
        if (success != null && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(success)));
        }
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
        }
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    profile.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (isSelf)
                  const Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('Toi'),
                  )
                else if (profile.status == 'archived')
                  const Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('Archivé'),
                  ),
              ],
            ),
            if (profile.username.trim().isNotEmpty)
              Text('Identifiant : ${profile.username}'),
            if (!profile.passwordSet && !isPending)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.hourglass_top, size: 16),
                  label: const Text('En attente de 1re connexion'),
                ),
              ),
            // Actions réservées aux autres comptes : l'admin ne se gère pas
            // lui-même.
            if (!isSelf) ...[
              if (isPending) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => run(
                      () =>
                          repository.updateProfileStatus(profile.id, 'active'),
                      success:
                          '${profile.displayName} peut maintenant se connecter.',
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Valider ce compte'),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: () async {
                      final confirmed = await _confirm(
                        context,
                        'Refuser et supprimer ce compte ?',
                        '${profile.displayName} sera supprimé définitivement. '
                            'Cette action est irréversible.',
                      );
                      if (!confirmed) return;
                      await run(
                        () => repository.deleteAccount(profile.id),
                        success: 'Compte supprimé.',
                      );
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Refuser et supprimer'),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final confirmed = await _confirm(
                          context,
                          'Réinitialiser le mot de passe ?',
                          '${profile.displayName} devra refaire une '
                              '« première connexion ».',
                        );
                        if (!confirmed) return;
                        await run(
                          () => repository.resetAccountPassword(profile.id),
                          success: 'Mot de passe réinitialisé.',
                        );
                      },
                      icon: const Icon(Icons.lock_reset, size: 18),
                      label: const Text('Réinitialiser le mot de passe'),
                    ),
                    if (profile.status == 'archived')
                      TextButton.icon(
                        onPressed: () => run(
                          () => repository.updateProfileStatus(
                            profile.id,
                            'active',
                          ),
                          success: 'Compte réactivé.',
                        ),
                        icon: const Icon(Icons.unarchive_outlined, size: 18),
                        label: const Text('Réactiver'),
                      )
                    else
                      TextButton.icon(
                        onPressed: () async {
                          final confirmed = await _confirm(
                            context,
                            'Archiver ce compte ?',
                            '${profile.displayName} ne pourra plus se '
                                'connecter. Ses pronostics sont conservés.',
                          );
                          if (!confirmed) return;
                          await run(
                            () => repository.updateProfileStatus(
                              profile.id,
                              'archived',
                            ),
                            success: 'Compte archivé.',
                          );
                        },
                        icon: const Icon(Icons.archive_outlined, size: 18),
                        label: const Text('Archiver'),
                      ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: () async {
                        final confirmed = await _confirm(
                          context,
                          'Supprimer ce compte ?',
                          '${profile.displayName} sera supprimé '
                              'définitivement, ainsi que tous ses pronostics. '
                              'Cette action est irréversible. Pour juste '
                              'l’empêcher de se connecter, utilise plutôt '
                              '« Archiver ».',
                        );
                        if (!confirmed) return;
                        await run(
                          () => repository.deleteAccount(profile.id),
                          success: 'Compte supprimé.',
                        );
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Supprimer'),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(
    BuildContext context,
    String title,
    String message,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
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
  }
}
