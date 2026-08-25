import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:as_grinta/features/season_wrapped/presentation/season_wrapped_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Entrée publique vers le bilan de saison.
///
/// Elle n'existe que lorsque le backend confirme qu'un vrai bilan est
/// disponible pour l'utilisateur. L'ancien aperçu administrateur ne doit
/// jamais rendre l'entrée visible pendant une saison en cours.
class SeasonWrappedEntryButton extends ConsumerWidget {
  const SeasonWrappedEntryButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available =
        ref.watch(seasonWrappedStateProvider).valueOrNull?.available ?? false;
    if (!available) return const SizedBox.shrink();

    // `SeasonWrappedButton` reçoit ici uniquement un état disponible : il
    // ouvre donc toujours le vrai bilan, jamais son ancien mode aperçu.
    return const SeasonWrappedButton();
  }
}
