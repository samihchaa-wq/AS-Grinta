import 'package:as_grinta/features/preferences/data/preferences_repository.dart';
import 'package:as_grinta/features/preferences/data/push_subscriptions_repository.dart';
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
            Text(
              'Notifications push',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const _PushNotificationsCard(),

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

class _PushNotificationsCard extends ConsumerWidget {
  const _PushNotificationsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(pushStatusProvider);

    return Card(
      child: statusAsync.when(
        loading: () => const ListTile(
          leading: Icon(Icons.notifications_outlined),
          title: Text('Notifications push'),
          trailing: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (_, __) => const ListTile(
          leading: Icon(Icons.notifications_off_outlined),
          title: Text('Notifications push indisponibles'),
        ),
        data: (status) {
          if (!status.supported) {
            return const ListTile(
              leading: Icon(Icons.notifications_off_outlined),
              title: Text('Notifications push'),
              subtitle: Text(
                'Non disponibles dans ce navigateur. Sur iPhone, installe '
                'd’abord l’application depuis Safari : Partager → '
                '« Sur l’écran d’accueil ».',
              ),
            );
          }
          return SwitchListTile.adaptive(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Recevoir les notifications'),
            subtitle: const Text(
              'Nouveau match, rappel avant la fermeture des pronostics et '
              'résultat validé, selon tes rappels ci-dessus.',
            ),
            value: status.subscribed,
            onChanged: (value) => _toggle(context, ref, value),
          );
        },
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    bool enable,
  ) async {
    final repository = ref.read(pushSubscriptionsRepositoryProvider);
    var message = '';
    try {
      if (enable) {
        final enabled = await repository.enable();
        message = enabled
            ? 'Notifications activées sur cet appareil.'
            : 'Autorisation refusée par le navigateur.';
      } else {
        await repository.disable();
        message = 'Notifications désactivées sur cet appareil.';
      }
    } catch (_) {
      message = 'Impossible de modifier les notifications.';
    }
    ref.invalidate(pushStatusProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
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
