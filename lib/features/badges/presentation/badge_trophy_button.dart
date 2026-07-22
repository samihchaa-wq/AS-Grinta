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
          children: [
            const Center(
              child: Text('🏆', style: TextStyle(fontSize: 28)),
            ),
            if (hasUnseen)
              Positioned(
                top: -2,
                right: -1,
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Text(
                    '1',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      height: 1,
                      fontWeight: FontWeight.w900,
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
