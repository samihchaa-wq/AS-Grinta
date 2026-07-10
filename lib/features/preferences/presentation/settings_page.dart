import 'package:as_grinta/features/preferences/data/preferences_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferencesAsync = ref.watch(appPreferencesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: preferencesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _SettingsError(
          onRetry: () => ref.invalidate(appPreferencesProvider),
        ),
        data: (preferences) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Rappels', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    title: const Text('Rappels de match'),
                    subtitle: const Text(
                      'Afficher les prochains matchs dans la page Rappels de l’application.',
                    ),
                    value: preferences.matchReminders,
                    onChanged: (value) => _save(
                      context,
                      ref,
                      preferences.copyWith(matchReminders: value),
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile.adaptive(
                    title: const Text('Rappels de pronostic'),
                    subtitle: const Text(
                      'Afficher les échéances de pronostic dans l’application.',
                    ),
                    value: preferences.predictionReminders,
                    onChanged: (value) => _save(
                      context,
                      ref,
                      preferences.copyWith(predictionReminders: value),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Application', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Card(
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.dark_mode_outlined),
                    title: Text('Thème sombre'),
                    subtitle: Text('Thème officiel AS Grinta'),
                    trailing: Icon(Icons.check_circle),
                  ),
                  Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.cloud_outlined),
                    title: Text('Données en ligne'),
                    subtitle: Text(
                      'Les données sont chargées depuis Supabase lorsque l’application est connectée.',
                    ),
                    trailing: Icon(Icons.check_circle),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    AppPreferences preferences,
  ) async {
    try {
      await ref.read(preferencesRepositoryProvider).update(preferences);
      ref.invalidate(appPreferencesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Préférences enregistrées.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Les préférences n’ont pas pu être enregistrées.'),
          ),
        );
      }
    }
  }
}

class _SettingsError extends StatelessWidget {
  const _SettingsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune_outlined, size: 52),
            const SizedBox(height: 14),
            Text(
              'Paramètres temporairement indisponibles',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualiser'),
            ),
          ],
        ),
      ),
    );
  }
}
