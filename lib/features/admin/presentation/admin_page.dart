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
          data: (dashboard) => ListView(
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
              const SizedBox(height: 8),
              if (dashboard.profiles.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('Aucun compte pour l’instant.'),
                  ),
                )
              else
                ...dashboard.profiles.map(
                  (profile) => _ProfileCard(profile: profile),
                ),
            ],
          ),
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  openSeason.predictionsLocked
                      ? 'Paris de saison verrouillés'
                      : 'Paris de saison ouverts',
                ),
                subtitle: Text(
                  openSeason.predictionsLocked
                      ? 'Verrouillés : les pronostics de chacun sont visibles '
                          'par tous et ne sont plus modifiables.'
                      : 'Ouverts : chacun saisit ses pronostics en secret. '
                          'Verrouille pour les révéler à tous et démarrer le '
                          'classement.',
                ),
                value: openSeason.predictionsLocked,
                onChanged: (lock) async {
                  if (lock) {
                    final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Verrouiller les paris ?'),
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
                                child: const Text('Verrouiller'),
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
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _changeStatus(
                      context,
                      ref,
                      openSeason,
                      'terminee',
                      title: 'Mettre fin à la saison ?',
                      message:
                          'La saison « ${openSeason.name} » sera marquée comme '
                          'terminée. Tu pourras la rouvrir plus tard.',
                    ),
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Mettre fin'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _changeStatus(
                      context,
                      ref,
                      openSeason,
                      'archived',
                      title: 'Archiver la saison ?',
                      message:
                          'La saison « ${openSeason.name} » sera archivée. '
                          'Tu pourras la rouvrir plus tard.',
                    ),
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text('Archiver'),
                  ),
                ],
              ),
            ],
            ..._otherSeasons(context, ref),
          ],
        ),
      ),
    );
  }

  /// Les saisons qui ne sont pas ouvertes (terminées ou archivées), avec la
  /// possibilité de les rouvrir ou de les archiver.
  List<Widget> _otherSeasons(BuildContext context, WidgetRef ref) {
    final others =
        dashboard.seasons.where((s) => s.status != 'open').toList();
    if (others.isEmpty) return const [];
    return [
      const Divider(height: 24),
      Text(
        'Autres saisons',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: 4),
      ...others.map(
        (season) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(season.name),
                    Text(
                      season.status == 'terminee' ? 'Terminée' : 'Archivée',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => _changeStatus(
                  context,
                  ref,
                  season,
                  'open',
                  title: 'Rouvrir la saison ?',
                  message:
                      'La saison « ${season.name} » redeviendra la saison en '
                      'cours. Toute autre saison ouverte sera archivée.',
                ),
                icon: const Icon(Icons.lock_open_outlined, size: 18),
                label: const Text('Rouvrir'),
              ),
              if (season.status == 'terminee')
                IconButton(
                  tooltip: 'Archiver',
                  onPressed: () => _changeStatus(
                    context,
                    ref,
                    season,
                    'archived',
                    title: 'Archiver la saison ?',
                    message: 'La saison « ${season.name} » sera archivée.',
                  ),
                  icon: const Icon(Icons.archive_outlined, size: 20),
                ),
            ],
          ),
        ),
      ),
    ];
  }

  Future<void> _changeStatus(
    BuildContext context,
    WidgetRef ref,
    AdminSeasonItem season,
    String status, {
    required String title,
    required String message,
  }) async {
    final confirmed = await showDialog<bool>(
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
      await ref.read(adminRepositoryProvider).setSeasonStatus(season.id, status);
      ref.invalidate(adminDashboardProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(error))),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(error))),
        );
      }
    }
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

    Future<void> run(
      Future<void> Function() action, {
      String? success,
    }) async {
      try {
        await action();
        ref.invalidate(adminDashboardProvider);
        if (success != null && context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(success)));
        }
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(humanizeError(error))));
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
            if (!profile.passwordSet)
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
              if (profile.status == 'pending')
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: FilledButton.icon(
                    onPressed: () => run(
                      () => repository.updateProfileStatus(profile.id, 'active'),
                      success:
                          '${profile.displayName} peut maintenant se connecter.',
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Valider ce compte'),
                  ),
                ),
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
                        () =>
                            repository.updateProfileStatus(profile.id, 'active'),
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
                              profile.id, 'archived'),
                          success: 'Compte archivé.',
                        );
                      },
                      icon: const Icon(Icons.archive_outlined, size: 18),
                      label: const Text('Archiver'),
                    ),
                ],
              ),
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
