import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Accès au bilan de saison, à côté de l'armoire à badges.
///
/// Le bouton n'existe qu'entre deux saisons : dès qu'une nouvelle saison est
/// créée, la base cesse de servir le bilan et le bouton disparaît. Il ne
/// s'affiche pas non plus pour un joueur qui n'a disputé aucun match.
///
/// Exception : un administrateur y a toujours accès, en aperçu, pour juger du
/// rendu sans attendre la fin d'une saison. L'aperçu affiche des chiffres
/// d'exemple et l'annonce clairement à l'écran.
class SeasonWrappedButton extends ConsumerWidget {
  const SeasonWrappedButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available =
        ref.watch(seasonWrappedStateProvider).valueOrNull?.available ?? false;
    final isAdmin = ref.watch(isAdminViewProvider);
    if (!available && !isAdmin) return const SizedBox.shrink();

    // Un vrai bilan prime toujours sur l'aperçu.
    final preview = !available;

    return IconButton(
      key: const ValueKey('season-wrapped-button'),
      tooltip: preview ? 'Ma saison (aperçu)' : 'Ma saison',
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      style: IconButton.styleFrom(
        foregroundColor: AppTheme.accent,
        backgroundColor: AppTheme.accent.withValues(alpha: .08),
        side: BorderSide(color: AppTheme.accent.withValues(alpha: .18)),
      ),
      icon: SizedBox(
        width: 30,
        height: 30,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              size: 21,
              color: AppTheme.accent,
            ),
            if (preview)
              Positioned(
                right: -3,
                bottom: -3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.admin,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'A',
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      onPressed: () => context.push(preview ? '/wrapped?apercu=1' : '/wrapped'),
    );
  }
}
