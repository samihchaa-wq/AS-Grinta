import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/widgets/admin_badge.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/preferences/data/preferences_repository.dart';
import 'package:as_grinta/features/preferences/data/push_subscriptions_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Notifications')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(pushStatusProvider)
            ..invalidate(appPreferencesProvider);
          await Future.wait([
            ref.read(pushStatusProvider.future),
            ref.read(appPreferencesProvider.future),
          ]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: const [
            _PushActivationCard(),
            SizedBox(height: 16),
            _MandatoryNotificationsCard(),
            SizedBox(height: 16),
            _OptionalNotificationsCard(),
            _TestPushButton(),
            _AdminCustomNotificationCard(),
            _AdminKillSwitchCard(),
          ],
        ),
      ),
    );
  }
}

class _MandatoryNotificationsCard extends StatelessWidget {
  const _MandatoryNotificationsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notifications essentielles',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Elles concernent directement l’organisation d’un match et ne '
              'peuvent pas être désactivées dans AS Grinta.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            _line(
              Icons.event_available_outlined,
              'Ouverture des disponibilités',
              'À J−6 à 12h, quand tu peux indiquer si tu es disponible.',
            ),
            _line(
              Icons.event_busy_outlined,
              'Match annulé',
              'Si un match est annulé après l’ouverture des disponibilités.',
            ),
            _line(
              Icons.update_outlined,
              'Match reporté ou horaire modifié',
              'Si la date change, ta disponibilité est redemandée. Si seule '
                  'l’heure change, ta réponse est conservée.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionalNotificationsCard extends ConsumerWidget {
  const _OptionalNotificationsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferencesAsync = ref.watch(appPreferencesProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'À toi de choisir',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Tu peux activer ou désactiver chaque notification séparément.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            preferencesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: GrintaProgressIndicator()),
              ),
              error: (_, __) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Impossible de charger tes préférences.'),
              ),
              data: (preferences) => Column(
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.sports_soccer_outlined),
                    title: const Text('Pronostics'),
                    subtitle: const Text('Un rappel à J−5 si tu n’as pas pronostiqué.'),
                    value: preferences.predictionNotifications,
                    onChanged: (value) => _update(
                      context,
                      ref,
                      preferences.copyWith(predictionNotifications: value),
                    ),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.workspace_premium_outlined),
                    title: const Text('Vote Homme du match'),
                    subtitle: const Text('Prévenu dès que le vote est ouvert.'),
                    value: preferences.motmVoteNotifications,
                    onChanged: (value) => _update(
                      context,
                      ref,
                      preferences.copyWith(motmVoteNotifications: value),
                    ),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.how_to_reg_outlined),
                    title: const Text('Convocations'),
                    subtitle: const Text(
                      'Prévenu si tu passes de la liste d’attente aux convoqués.',
                    ),
                    value: preferences.convocationNotifications,
                    onChanged: (value) => _update(
                      context,
                      ref,
                      preferences.copyWith(convocationNotifications: value),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _update(
    BuildContext context,
    WidgetRef ref,
    AppPreferences preferences,
  ) async {
    try {
      await ref.read(preferencesRepositoryProvider).update(preferences);
      ref.invalidate(appPreferencesProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d’enregistrer ce réglage.')),
        );
      }
    }
  }
}

class _TestPushButton extends ConsumerStatefulWidget {
  const _TestPushButton();

  @override
  ConsumerState<_TestPushButton> createState() => _TestPushButtonState();
}

class _TestPushButtonState extends ConsumerState<_TestPushButton> {
  bool _sending = false;

  Future<void> _send() async {
    setState(() => _sending = true);
    var message = 'Test envoyé — regarde tes notifications.';
    try {
      await ref.read(supabaseClientProvider).rpc('send_test_push');
    } catch (_) {
      message = 'Impossible d’envoyer le test.';
    }
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: OutlinedButton.icon(
        onPressed: _sending ? null : _send,
        icon: _sending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: GrintaProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.send_outlined),
        label: const Text('M’envoyer un test'),
      ),
    );
  }
}

final notificationsPausedProvider = FutureProvider.autoDispose<bool>((ref) async {
  final response = await ref
      .read(supabaseClientProvider)
      .rpc('admin_get_notifications_paused');
  final map = Map<String, dynamic>.from(response as Map);
  final flag = Map<String, dynamic>.from(
    map['notifications_paused'] as Map? ?? const {},
  );
  return flag['enabled'] == true;
});

class _AdminCustomNotificationCard extends ConsumerWidget {
  const _AdminCustomNotificationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isAdminViewProvider)) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.campaign_outlined),
          title: const Row(
            children: [
              AdminBadge(),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Envoyer une notification',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          subtitle: const Text('Écris un message et choisis qui le reçoit.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/admin/notification'),
        ),
      ),
    );
  }
}

class _AdminKillSwitchCard extends ConsumerStatefulWidget {
  const _AdminKillSwitchCard();

  @override
  ConsumerState<_AdminKillSwitchCard> createState() =>
      _AdminKillSwitchCardState();
}

class _AdminKillSwitchCardState extends ConsumerState<_AdminKillSwitchCard> {
  bool _updating = false;

  Future<void> _toggle(bool enable) async {
    setState(() => _updating = true);
    var message = enable
        ? 'Toutes les notifications sont désactivées.'
        : 'Les notifications sont réactivées.';
    try {
      await ref.read(supabaseClientProvider).rpc(
        'admin_set_notifications_paused',
        params: {'p_enabled': enable},
      );
      ref.invalidate(notificationsPausedProvider);
    } catch (_) {
      message = 'Impossible de modifier ce réglage.';
    }
    if (!mounted) return;
    setState(() => _updating = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(isAdminViewProvider)) return const SizedBox.shrink();
    final pausedAsync = ref.watch(notificationsPausedProvider);
    final paused = pausedAsync.valueOrNull ?? false;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        color: paused ? const Color(0xFF3A1F22) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AdminBadge(),
              const SizedBox(height: 8),
              Text(
                'Toutes les notifications',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                paused
                    ? 'Désactivées : aucun joueur ne reçoit rien, y compris le test.'
                    : 'Coupe temporairement tous les envois sans modifier les '
                        'préférences des joueurs.',
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Désactiver toutes les notifications'),
                value: paused,
                onChanged: (_updating || pausedAsync.isLoading)
                    ? null
                    : (value) => _toggle(value),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PushActivationCard extends ConsumerStatefulWidget {
  const _PushActivationCard();

  @override
  ConsumerState<_PushActivationCard> createState() => _PushActivationCardState();
}

class _PushActivationCardState extends ConsumerState<_PushActivationCard> {
  bool _enabling = false;

  Future<void> _enable() async {
    setState(() => _enabling = true);
    var message = 'Notifications activées sur cet appareil.';
    try {
      final enabled =
          await ref.read(pushSubscriptionsRepositoryProvider).enable();
      if (!enabled) message = 'Autorisation refusée par le navigateur.';
    } catch (_) {
      message = 'Impossible d’activer les notifications.';
    }
    ref.invalidate(pushStatusProvider);
    if (!mounted) return;
    setState(() => _enabling = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(pushStatusProvider);

    return Card(
      child: statusAsync.when(
        loading: () => const ListTile(
          leading: Icon(Icons.notifications_outlined),
          title: Text('Notifications push'),
          trailing: SizedBox(
            width: 20,
            height: 20,
            child: GrintaProgressIndicator(strokeWidth: 2),
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

          if (status.subscribed) {
            return const ListTile(
              leading: Icon(Icons.notifications_active_outlined),
              title: Text('Notifications activées'),
              subtitle: Text(
                'Les notifications essentielles restent actives. Tu peux '
                'personnaliser les notifications facultatives ci-dessous.',
              ),
              trailing: Icon(Icons.check_circle_outline),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.notifications_outlined),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Notifications désactivées sur cet appareil',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Active-les pour recevoir les informations essentielles '
                  'liées aux matchs.',
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _enabling ? null : _enable,
                  icon: _enabling
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: GrintaProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.notifications_active_outlined),
                  label: const Text('Activer les notifications'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
