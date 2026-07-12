import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/features/admin/data/admin_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Comptes et effectif',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _invitePlayer(context, ref),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Inviter'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      const ClipboardData(text: _registerLink),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Lien d’inscription copié — partage-le sur '
                            'WhatsApp. Tu valideras ensuite chaque compte ici.',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('Copier le lien d’inscription'),
                ),
              ),
              const SizedBox(height: 4),
              if (dashboard.profiles.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('Aucun compte disponible.'),
                  ),
                )
              else
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

  Future<void> _invitePlayer(BuildContext context, WidgetRef ref) async {
    final firstName = TextEditingController();
    final lastInitial = TextEditingController();
    final nickname = TextEditingController();
    var isGoalkeeper = false;
    var saving = false;
    String? error;

    await showDialog<void>(
      context: context,
      barrierDismissible: !saving,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Inviter un joueur'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: firstName,
                  decoration: const InputDecoration(labelText: 'Prénom'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: lastInitial,
                  maxLength: 1,
                  decoration: const InputDecoration(
                    labelText: 'Première lettre du nom',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nickname,
                  decoration: const InputDecoration(
                    labelText: 'Surnom (facultatif)',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Gardien'),
                  value: isGoalkeeper,
                  onChanged: saving
                      ? null
                      : (value) => setState(() => isGoalkeeper = value),
                ),
                if (error != null)
                  Text(
                    error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (firstName.text.trim().isEmpty ||
                          lastInitial.text.trim().isEmpty) {
                        setState(
                          () => error =
                              'Le prénom et la première lettre du nom sont obligatoires.',
                        );
                        return;
                      }
                      setState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        final username = await ref
                            .read(adminRepositoryProvider)
                            .inviteAccount(
                              firstName: firstName.text,
                              lastInitial: lastInitial.text,
                              surnom: nickname.text,
                              isGoalkeeper: isGoalkeeper,
                            );
                        ref.invalidate(adminDashboardProvider);
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        await showDialog<void>(
                          context: context,
                          builder: (resultContext) => AlertDialog(
                            title: const Text('Compte créé'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Communique cet identifiant au joueur. Il '
                                  'choisira son mot de passe à sa première '
                                  'connexion (« Première connexion ? » sur '
                                  'l’écran d’accueil).',
                                ),
                                const SizedBox(height: 12),
                                SelectableText(
                                  username,
                                  style: Theme.of(resultContext)
                                      .textTheme
                                      .headlineSmall,
                                ),
                              ],
                            ),
                            actions: [
                              TextButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: username),
                                  );
                                },
                                icon: const Icon(Icons.copy),
                                label: const Text('Copier'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(resultContext),
                                child: const Text('Fermer'),
                              ),
                            ],
                          ),
                        );
                      } catch (exception) {
                        if (!dialogContext.mounted) return;
                        setState(() {
                          saving = false;
                          error = exception.toString();
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Créer le compte'),
            ),
          ],
        ),
      ),
    );

    firstName.dispose();
    lastInitial.dispose();
    nickname.dispose();
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
                title: const Text('Pronostics de saison ouverts'),
                subtitle: Text(
                  openSeason.predictionsLocked
                      ? 'Fermés : plus personne ne peut les modifier.'
                      : 'Ouverts : chacun peut encore les modifier.',
                ),
                value: !openSeason.predictionsLocked,
                onChanged: (open) async {
                  try {
                    await ref
                        .read(adminRepositoryProvider)
                        .setSeasonPredictionsLock(
                          seasonId: openSeason.id,
                          locked: !open,
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
              OutlinedButton.icon(
                onPressed: () async {
                  await ref
                      .read(adminRepositoryProvider)
                      .archiveSeason(openSeason.id);
                  ref.invalidate(adminDashboardProvider);
                },
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Archiver'),
              ),
            ],
          ],
        ),
      ),
    );
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
    if (name == null) return;
    await ref.read(adminRepositoryProvider).createSeason(name);
    ref.invalidate(adminDashboardProvider);
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
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              profile.displayName,
              style: Theme.of(context).textTheme.titleMedium,
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
            if (profile.status == 'pending')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.how_to_reg_outlined, size: 16),
                        label: const Text('En attente de validation'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: () async {
                        try {
                          await repository.updateProfileStatus(
                            profile.id,
                            'active',
                          );
                          ref.invalidate(adminDashboardProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${profile.displayName} peut maintenant '
                                  'se connecter et pronostiquer.',
                                ),
                              ),
                            );
                          }
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(humanizeError(error))),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Valider'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: profile.role,
              decoration: const InputDecoration(labelText: 'Rôle'),
              items: const [
                DropdownMenuItem(
                  value: 'pronostiqueur',
                  child: Text('Joueur'),
                ),
                DropdownMenuItem(
                  value: 'moderateur',
                  child: Text('Modérateur'),
                ),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
              ],
              onChanged: (value) async {
                if (value == null || value == profile.role) return;
                // Confirmation lors d'une élévation de privilèges : accorder
                // les droits staff est une action sensible.
                if (value == 'admin' || value == 'moderateur') {
                  final roleLabel =
                      value == 'admin' ? 'administrateur' : 'modérateur';
                  final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Accorder des droits ?'),
                          content: Text(
                            'Donner le rôle « $roleLabel » à '
                            '${profile.displayName} lui ouvre l’accès à '
                            'l’administration. Continuer ?',
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
                              child: const Text('Confirmer'),
                            ),
                          ],
                        ),
                      ) ??
                      false;
                  if (!confirmed) return;
                }
                try {
                  await repository.updateProfileRole(profile.id, value);
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Joueur (feuille de match)'),
                value: profile.inOpenSeason,
                onChanged: (value) async {
                  await repository.setSeasonMembership(
                    seasonId: openSeasonId!,
                    profile: profile,
                    selected: value,
                  );
                  ref.invalidate(adminDashboardProvider);
                },
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Réinitialiser le mot de passe ?'),
                          content: Text(
                            '${profile.displayName} devra refaire une '
                            '« première connexion » et choisir un nouveau '
                            'mot de passe.',
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
                              child: const Text('Réinitialiser'),
                            ),
                          ],
                        ),
                      ) ??
                      false;
                  if (!confirmed) return;
                  try {
                    await repository.resetAccountPassword(profile.id);
                    ref.invalidate(adminDashboardProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Mot de passe réinitialisé : ${profile.username} '
                            'doit refaire sa première connexion.',
                          ),
                        ),
                      );
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('La réinitialisation a échoué.'),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.lock_reset, size: 18),
                label: const Text('Réinitialiser le mot de passe'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
