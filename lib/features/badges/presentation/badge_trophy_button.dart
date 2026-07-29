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
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      style: IconButton.styleFrom(
        foregroundColor: AppTheme.reward,
        backgroundColor: AppTheme.reward.withValues(alpha: .08),
        side: BorderSide(color: AppTheme.reward.withValues(alpha: .18)),
      ),
      icon: SizedBox(
        width: 30,
        height: 30,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            const Icon(
              Icons.emoji_events_rounded,
              size: 21,
              color: AppTheme.reward,
            ),
            const ExcludeSemantics(
              child: Opacity(opacity: 0, child: Text('🏆')),
            ),
            if (hasUnseen)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  key: const ValueKey('badge-unseen-indicator'),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.background, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accent.withValues(alpha: .28),
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
