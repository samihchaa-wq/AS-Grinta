import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bandeau affiché en haut de l'application tant qu'un admin la regarde
/// comme un joueur : il sait toujours qu'il est en aperçu et revient à sa
/// vue en un geste, depuis n'importe quel écran.
class PlayerPreviewBanner extends ConsumerWidget {
  const PlayerPreviewBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isPlayerPreviewActiveProvider)) {
      return const SizedBox.shrink();
    }
    return Material(
      key: const ValueKey('player-preview-banner'),
      color: AppTheme.admin,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(
          children: [
            const Icon(Icons.visibility_outlined,
                size: 18, color: AppTheme.background),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Vue joueur',
                maxLines: 2,
                style: TextStyle(color: AppTheme.background, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(playerPreviewProvider.notifier).state = false,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.background,
              ),
              child: const Text('Revenir en admin'),
            ),
          ],
        ),
      ),
    );
  }
}
