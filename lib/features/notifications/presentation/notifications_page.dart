import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/preferences/data/push_subscriptions_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Notifications')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(pushStatusProvider);
          await ref.read(pushStatusProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: const [
            _PushActivationCard(),
            SizedBox(height: 16),
            _NotificationsInfoCard(),
            _AdminTestButton(),
          ],
        ),
      ),
    );
  }
}

class _NotificationsInfoCard extends StatelessWidget {
  const _NotificationsInfoCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ce que tu reçois',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _line('📅', 'La demande de disponibilité, avec un rappel de '
                'pronostiquer.'),
            _line('🏁', 'Le score final de chaque match.'),
            _line('👑', 'L’invitation à voter pour l’Homme du match, si tu '
                'étais présent.'),
            _line('🎉', 'Le résultat du vote, si tu as voté.'),
          ],
        ),
      ),
    );
  }

  Widget _line(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

/// Bouton réservé à l'admin : envoie une notification de test à soi-même
/// uniquement, pour valider le rendu sans déranger l'équipe.
class _AdminTestButton extends ConsumerStatefulWidget {
  const _AdminTestButton();

  @override
  ConsumerState<_AdminTestButton> createState() => _AdminTestButtonState();
}

class _AdminTestButtonState extends ConsumerState<_AdminTestButton> {
  bool _sending = false;

  Future<void> _send() async {
    setState(() => _sending = true);
    var message = 'Test envoyé — regarde tes notifications.';
    try {
      await ref.read(supabaseClientProvider).rpc('admin_send_test_push');
    } catch (_) {
      message = 'Impossible d’envoyer le test.';
    }
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isStaff =
        ref.watch(authControllerProvider).profile?.role.isStaff == true;
    if (!isStaff) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: OutlinedButton.icon(
        onPressed: _sending ? null : _send,
        icon: _sending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.send_outlined),
        label: const Text('M’envoyer un test'),
      ),
    );
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
              'Active ceci pour être prévenu des matchs, des votes et des '
              'résultats de l’équipe.',
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
