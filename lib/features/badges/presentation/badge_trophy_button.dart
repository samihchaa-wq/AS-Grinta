import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/badges/data/badge_inbox_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class BadgeTrophyButton extends ConsumerWidget {
  const BadgeTrophyButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasUnseen = ref.watch(hasUnseenBadgeProvider).valueOrNull ?? false;

    return IconButton(
      tooltip: 'Armoire à badges',
      // Le carré, le fond et la bordure viennent du style commun des actions
      // de la barre du haut ; seul l'or des récompenses reste propre au
      // trophée.
      style: IconButton.styleFrom(foregroundColor: AppTheme.reward),
      icon: SizedBox(
        width: 22,
        height: 22,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            const Icon(
              Icons.emoji_events_rounded,
              size: 19,
              color: AppTheme.reward,
            ),
            const ExcludeSemantics(
              child: Opacity(opacity: 0, child: Text('🏆')),
            ),
            if (hasUnseen)
              Positioned(
                top: -5,
                right: -5,
                child: Container(
                  key: const ValueKey('badge-unseen-indicator'),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppTheme.reward,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.background, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.reward.withValues(alpha: .28),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      onPressed: () async {
        try {
          await ref.read(badgeInboxRepositoryProvider).markSeen();
          ref.invalidate(hasUnseenBadgeProvider);
        } catch (_) {
          // L'armoire reste accessible même si l'acquittement échoue.
        }
        if (context.mounted) context.push('/armoire');
      },
    );
  }
}
