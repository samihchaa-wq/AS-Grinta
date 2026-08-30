part of 'admin_page.dart';

class _SeasonCard extends ConsumerWidget {
  const _SeasonCard({
    required this.dashboard,
    required this.onSeasonCreated,
  });

  final AdminDashboardData dashboard;
  final VoidCallback onSeasonCreated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openSeasons = dashboard.seasons.where(
      (item) => item.status == 'open',
    );
    final openSeason = openSeasons.isEmpty ? null : openSeasons.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (openSeason != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  textStyle: Theme.of(context).textTheme.titleLarge,
                ),
                onPressed: () => _changeStatus(
                  context,
                  ref,
                  openSeason,
                  'archived',
                  title: 'Finir la saison ?',
                  message: 'La saison « ${openSeason.name} » sera archivée '
                      'immédiatement et le classement final figé. '
                      'C’est définitif. Tu pourras ensuite créer une '
                      'nouvelle saison.',
                ),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Finir la saison'),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: openSeason == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Paris buteur',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => _createSeason(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Créer une saison'),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Paris buteur',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Switch.adaptive(
                        value: !openSeason.predictionsLocked,
                        onChanged: (enabled) async {
                          final lock = !enabled;
                          if (lock) {
                            final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (dialogContext) => AlertDialog(
                                    title: const Text('Fermer les paris ?'),
                                    content: const Text(
                                      'Les pronostics de saison de tout le '
                                      'monde deviendront visibles et ne '
                                      'pourront plus être modifiés. Le '
                                      'classement de saison démarre.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(
                                          dialogContext,
                                          false,
                                        ),
                                        child: const Text('Annuler'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.pop(
                                          dialogContext,
                                          true,
                                        ),
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
                    ],
                  ),
          ),
        ),
      ],
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
        onSeasonCreated();
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
