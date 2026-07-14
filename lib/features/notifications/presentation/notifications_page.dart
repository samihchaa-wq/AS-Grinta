import 'package:as_grinta/features/notifications/data/notifications_repository.dart';
import 'package:as_grinta/features/preferences/data/preferences_repository.dart';
import 'package:as_grinta/features/preferences/data/push_subscriptions_repository.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);
    final preferencesAsync = ref.watch(appPreferencesProvider);
    // Les « Me prévenir… » sont gouvernés par l'interrupteur principal :
    // tant qu'on ne reçoit pas les notifications sur cet appareil, ils sont
    // désactivés (et remis à zéro dès qu'on coupe le principal).
    final pushSubscribed =
        ref.watch(pushStatusProvider).valueOrNull?.subscribed ?? false;

    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Notifications')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(appPreferencesProvider);
          ref.invalidate(notificationsProvider);
          await ref.read(notificationsProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const _PushActivationCard(),
            const SizedBox(height: 16),
            Text(
              'Me prévenir…',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            preferencesAsync.when(
              loading: () => const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (_, __) => Card(
                child: ListTile(
                  title: const Text('Préférences indisponibles'),
                  trailing: IconButton(
                    onPressed: () => ref.invalidate(appPreferencesProvider),
                    icon: const Icon(Icons.refresh),
                  ),
                ),
              ),
              data: (preferences) => Card(
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      title: const Text('Quand un pronostic est ouvert'),
                      subtitle: const Text(
                        'Dès qu’un nouveau match est annoncé.',
                      ),
                      value: pushSubscribed && preferences.predictionOpen,
                      onChanged: pushSubscribed
                          ? (value) => _save(
                                context,
                                ref,
                                preferences.copyWith(predictionOpen: value),
                              )
                          : null,
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      title: const Text('2 h avant le match'),
                      subtitle: const Text(
                        'Seulement si tu n’as pas encore pronostiqué.',
                      ),
                      value: pushSubscribed && preferences.predictionReminders,
                      onChanged: pushSubscribed
                          ? (value) => _save(
                                context,
                                ref,
                                preferences.copyWith(
                                    predictionReminders: value),
                              )
                          : null,
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      title: const Text('Quand le match est fini'),
                      subtitle: const Text(
                        'Points gagnés et pronostics des autres révélés.',
                      ),
                      value: pushSubscribed && preferences.matchReminders,
                      onChanged: pushSubscribed
                          ? (value) => _save(
                                context,
                                ref,
                                preferences.copyWith(matchReminders: value),
                              )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'À venir',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            notificationsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Rappels temporairement indisponibles.'),
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Aucun rappel : les prochains matchs apparaîtront ici.',
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final item in items) ...[
                      Card(
                        child: ListTile(
                          leading:
                              CircleAvatar(child: Icon(_iconFor(item.kind))),
                          title: Text(item.title),
                          subtitle: Text(
                            '${item.message}\n${_formatDate(item.date)}',
                          ),
                          isThreeLine: true,
                          onTap: item.kind == 'prediction'
                              ? () => context.push('/predictions')
                              : () => context.push('/matches'),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },
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
      ref.invalidate(notificationsProvider);
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

  IconData _iconFor(String kind) {
    return kind == 'prediction'
        ? Icons.auto_awesome_outlined
        : Icons.sports_soccer_outlined;
  }

  String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} à '
        '${two(date.hour)}:${two(date.minute)}';
  }
}

class _PushActivationCard extends ConsumerWidget {
  const _PushActivationCard();

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
            title: const Text('Recevoir les notifications sur cet appareil'),
            subtitle: const Text(
              'Active d’abord ceci, puis choisis en dessous quand être '
              'prévenu.',
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
