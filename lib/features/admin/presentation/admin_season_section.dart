part of 'admin_page.dart';

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
            Text(
              openSeason == null
                  ? 'Aucune saison en cours'
                  : 'Saison ${openSeason.name}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (openSeason == null)
              FilledButton(
                onPressed: () => _createSeason(context, ref),
                child: const Text('Créer une saison'),
              )
            else
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  padding: const EdgeInsets.symmetric(horizontal: 0),
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
                child: const Text('Finir la saison'),
              ),
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
              'effectif dans Paramètres › Effectif.',
            ),
          ),
        );
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
