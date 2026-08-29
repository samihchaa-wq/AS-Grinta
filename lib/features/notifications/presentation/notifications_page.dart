import 'package:as_grinta/core/providers/supabase_provider.dart';
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: const [
            _PushActivationCard(),
            _MandatoryNotificationsCard(),
            SizedBox(height: 12),
            _OptionalNotificationsCard(),
            _NotificationActionsRow(),
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
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            _line(
              Icons.event_available_outlined,
              'Ouverture des disponibilités',
            ),
            _line(Icons.event_busy_outlined, 'Match annulé'),
            _line(
              Icons.update_outlined,
              'Match reporté ou horaire modifié',
              bottomPadding: 0,
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(
    IconData icon,
    String title, {
    double bottomPadding = 10,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Row(
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: preferencesAsync.when(
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
                title: const Text('Ouverture pronostique'),
                value: preferences.predictionNotifications,
                onChanged: (value) => _update(
                  context,
                  ref,
                  preferences.copyWith(predictionNotifications: value),
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Vote Homme du Match'),
                value: preferences.motmVoteNotifications,
                onChanged: (value) => _update(
                  context,
                  ref,
                  preferences.copyWith(motmVoteNotifications: value),
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Passage en convoqué'),
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

class _NotificationActionsRow extends ConsumerWidget {
  const _NotificationActionsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminViewProvider);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          const Expanded(child: _TestPushButton()),
          if (isAdmin) ...[
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => context.push('/admin/notification'),
                child: const Text(
                  'Envoyer un notif.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ],
      ),
    );
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
      final result =
          await ref.read(supabaseClientProvider).rpc('send_test_push');
      final data = result is Map ? Map<String, dynamic>.from(result) : null;
      if (data != null && data['sent'] != true) {
        message = switch (data['reason']?.toString()) {
          'no_subscription' =>
            'Aucun appareil abonné : active les notifications sur cet appareil.',
          'notifications_paused' =>
            'Les notifications du club sont en pause : rien n’a été envoyé.',
          'not_configured' => 'Les notifications push ne sont pas configurées.',
          _ => 'Impossible d’envoyer le test.',
        };
      }
    } catch (_) {
      message = 'Impossible d’envoyer le test.';
    }
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: _sending ? null : _send,
      child: _sending
          ? const SizedBox(
              width: 18,
              height: 18,
              child: GrintaProgressIndicator(strokeWidth: 2),
            )
          : const Text('Test'),
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
      await ref
          .read(supabaseClientProvider)
          .rpc('admin_set_notifications_paused', params: {'p_enabled': enable});
      ref.invalidate(notificationsPausedProvider);
    } catch (_) {
      message = 'Impossible de modifier ce réglage.';
    }
    if (!mounted) return;
    setState(() => _updating = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(isAdminViewProvider)) return const SizedBox.shrink();
    final pausedAsync = ref.watch(notificationsPausedProvider);
    final paused = pausedAsync.valueOrNull ?? false;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        color: paused ? const Color(0xFF3A1F22) : null,
        child: SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const Text('Désactiver toutes les notifications'),
          value: paused,
          onChanged: (_updating || pausedAsync.isLoading)
              ? null
              : (value) => _toggle(value),
        ),
      ),
    );
  }
}

class _PushActivationCard extends ConsumerStatefulWidget {
  const _PushActivationCard();

  @override
  ConsumerState<_PushActivationCard> createState() =>
      _PushActivationCardState();
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(pushStatusProvider);

    return statusAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const _CompactPushStatus(
        icon: Icons.notifications_off_outlined,
        label: 'Notifications push indisponibles',
      ),
      data: (status) {
        if (status.subscribed) return const SizedBox.shrink();

        if (!status.supported) {
          return const _CompactPushStatus(
            icon: Icons.notifications_off_outlined,
            label: 'Notifications indisponibles sur cet appareil',
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Notifications désactivées'),
              trailing: _enabling
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: GrintaProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: _enable,
                      child: const Text('Activer'),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _CompactPushStatus extends StatelessWidget {
  const _CompactPushStatus({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(label),
        ),
      ),
    );
  }
}
