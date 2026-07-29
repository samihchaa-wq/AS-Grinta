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
      padding: const EdgeInsets.symmetric(horizontal: 6),
      constraints: const BoxConstraints(),
      icon: SizedBox(
        width: 38,
        height: 38,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.reward.withValues(alpha: .12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.reward.withValues(alpha: .38),
                ),
              ),
              child: const Icon(
                Icons.emoji_events_rounded,
                size: 21,
                color: AppTheme.reward,
              ),
            ),
            if (hasUnseen)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.background,
                      width: 2,
                    ),
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
