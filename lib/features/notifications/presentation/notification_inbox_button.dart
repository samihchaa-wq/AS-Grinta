import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/notifications/data/notification_inbox_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Cloche de l'en-tête, à côté du trophée : ouvre l'historique des
/// notifications. Un petit chiffre indique combien n'ont pas été lues.
class NotificationInboxButton extends ConsumerWidget {
  const NotificationInboxButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;
    final label = unread == 0
        ? 'Notifications'
        : 'Notifications, $unread non ${unread > 1 ? 'lues' : 'lue'}';

    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      child: IconButton(
        key: const ValueKey('notification-inbox-button'),
        tooltip: 'Notifications',
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        style: IconButton.styleFrom(
          foregroundColor: AppTheme.primaryBright,
          backgroundColor: AppTheme.primaryBright.withValues(alpha: .08),
          side: BorderSide(
            color: AppTheme.primaryBright.withValues(alpha: .18),
          ),
        ),
        icon: SizedBox(
          width: 30,
          height: 30,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              const Icon(
                Icons.notifications_outlined,
                size: 26,
                color: AppTheme.primaryBright,
              ),
              if (unread > 0)
                Positioned(
                  top: -6,
                  right: -7,
                  child: _UnreadPill(count: unread),
                ),
            ],
          ),
        ),
        onPressed: () => context.push('/notifications'),
      ),
    );
  }
}

class _UnreadPill extends StatelessWidget {
  const _UnreadPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('notification-unread-pill'),
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // Texte sombre sur rouge : le blanc y serait trop peu lisible.
        color: AppTheme.error,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppTheme.background, width: 2),
      ),
      child: Text(
        count > 9 ? '9+' : '$count',
        // La pastille garde sa taille quel que soit le réglage de texte.
        textScaler: TextScaler.noScaling,
        style: const TextStyle(
          color: AppTheme.background,
          fontSize: 10,
          height: 1.1,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}
