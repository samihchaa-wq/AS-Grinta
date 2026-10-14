import 'package:as_grinta/core/widgets/grinta_status_banner.dart';
import 'package:as_grinta/features/preferences/data/push_subscriptions_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bandeau du haut de l'application quand cet appareil ne recevra pas les
/// notifications du club sans que le joueur l'ait choisi.
///
/// Sans lui, rien ne prévenait le joueur : il fallait ouvrir l'écran des
/// notifications pour voir la cloche grise, et un téléphone qui bloquait
/// l'affichage dans ses réglages gardait même une cloche verte.
class PushDeviceBanner extends ConsumerStatefulWidget {
  const PushDeviceBanner({super.key});

  @override
  ConsumerState<PushDeviceBanner> createState() => _PushDeviceBannerState();
}

class _PushDeviceBannerState extends ConsumerState<PushDeviceBanner> {
  bool _busy = false;

  void _say(String message) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _enable() async {
    setState(() => _busy = true);
    var enabled = false;
    try {
      enabled = await ref.read(pushSubscriptionsRepositoryProvider).enable();
    } catch (_) {
      enabled = false;
    }
    ref.invalidate(pushStatusProvider);
    if (!mounted) return;
    setState(() => _busy = false);
    _say(
      enabled
          ? 'Notifications activées sur cet appareil.'
          : 'Notifications bloquées sur ce téléphone : autorise-les dans '
              'ses réglages, puis réessaie.',
    );
  }

  Future<void> _recheck() async {
    ref.invalidate(pushStatusProvider);
    final alert = await ref.read(pushDeviceAlertProvider.future);
    if (!mounted || alert != PushDeviceAlert.blocked) return;
    _say(
      'Toujours bloquées : ouvre les réglages du téléphone, rubrique '
      'Notifications, et autorise ASG.',
    );
  }

  Future<void> _decline() async {
    await writePushOptOut(true);
    ref.invalidate(pushStatusProvider);
  }

  @override
  Widget build(BuildContext context) {
    final alert = ref.watch(pushDeviceAlertProvider).valueOrNull;
    if (alert == null || alert == PushDeviceAlert.none) {
      return const SizedBox.shrink();
    }

    final blocked = alert == PushDeviceAlert.blocked;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: GrintaStatusBanner(
            title: blocked
                ? 'Notifications bloquées'
                : 'Notifications désactivées',
            message: blocked
                ? 'Ton téléphone n’affiche pas les notifications du club. '
                    'Autorise-les dans ses réglages pour être prévenu des '
                    'disponibilités et des convocations.'
                : 'Tu ne reçois pas les notifications du club sur cet '
                    'appareil : ouverture des disponibilités, convocations.',
            tone: GrintaStatusTone.warning,
            compact: true,
            action: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : (blocked ? _recheck : _enable),
                  child: Text(blocked ? 'C’est fait' : 'Activer'),
                ),
                TextButton(
                  onPressed: _busy ? null : _decline,
                  child: const Text('Non merci'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
