import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/features/match_live/data/match_live_notification_repository.dart';
import 'package:as_grinta/features/preferences/data/push_subscriptions_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MatchLiveNotificationBell extends ConsumerStatefulWidget {
  const MatchLiveNotificationBell({
    super.key,
    required this.matchId,
    required this.subscribed,
  });

  final String matchId;
  final bool subscribed;

  @override
  ConsumerState<MatchLiveNotificationBell> createState() =>
      _MatchLiveNotificationBellState();
}

class _MatchLiveNotificationBellState
    extends ConsumerState<MatchLiveNotificationBell> {
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);

    final enable = !widget.subscribed;
    try {
      if (enable) {
        // L'abonnement au match est lié au compte, mais cet appareil doit
        // aussi posséder un abonnement Web Push valide pour recevoir l'alerte.
        // enable() réenregistre l'endpoint côté serveur de façon idempotente.
        final pushReady =
            await ref.read(pushSubscriptionsRepositoryProvider).enable();
        if (!pushReady) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Autorise les notifications sur cet appareil pour activer la cloche.',
              ),
            ),
          );
          return;
        }
        ref.invalidate(pushStatusProvider);
      }

      await ref.read(matchLiveNotificationRepositoryProvider).setEnabled(
            matchId: widget.matchId,
            enabled: enable,
          );
      ref.invalidate(matchLiveNotificationStatusProvider(widget.matchId));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enable
                ? 'Alertes de buts activées pour ce match.'
                : 'Alertes de buts désactivées pour ce match.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(humanizeError(error))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subscribed = widget.subscribed;
    final color = subscribed ? AppTheme.success : AppTheme.textFaint;

    return Semantics(
      button: true,
      toggled: subscribed,
      label: subscribed
          ? 'Désactiver les alertes de buts'
          : 'Activer les alertes de buts',
      child: IconButton(
        tooltip: subscribed
            ? 'Désactiver les alertes de buts'
            : 'Activer les alertes de buts',
        onPressed: _busy ? null : _toggle,
        icon: _busy
            ? SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: color,
                ),
              )
            : Icon(
                subscribed
                    ? Icons.notifications_rounded
                    : Icons.notifications_none_rounded,
                color: color,
              ),
      ),
    );
  }
}
