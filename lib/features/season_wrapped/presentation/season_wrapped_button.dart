import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Accès au bilan de saison, à côté de l'armoire à badges.
///
/// Le bouton n'existe qu'entre deux saisons : dès qu'une nouvelle saison est
/// créée, la base cesse de servir le bilan et le bouton disparaît. Il ne
/// s'affiche pas non plus pour un joueur qui n'a disputé aucun match.
class SeasonWrappedButton extends ConsumerWidget {
  const SeasonWrappedButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available =
        ref.watch(seasonWrappedStateProvider).valueOrNull?.available ?? false;
    if (!available) return const SizedBox.shrink();

    return IconButton(
      key: const ValueKey('season-wrapped-button'),
      tooltip: 'Ma saison',
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      style: IconButton.styleFrom(
        foregroundColor: AppTheme.accent,
        backgroundColor: AppTheme.accent.withValues(alpha: .08),
        side: BorderSide(color: AppTheme.accent.withValues(alpha: .18)),
      ),
      icon: const SizedBox(
        width: 30,
        height: 30,
        child: Center(
          child: Icon(
            Icons.auto_awesome_rounded,
            size: 21,
            color: AppTheme.accent,
          ),
        ),
      ),
      onPressed: () => context.push('/wrapped'),
    );
  }
}
