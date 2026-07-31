import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/match_live/domain/match_live_session.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_pre_kickoff_page.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_running_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Point d'entrée de l'onglet "Tableau blanc" dans la fiche du match :
/// aiguille vers l'écran de préparation, le direct ou le récapitulatif selon
/// l'état de la session live, et vers une vue lecture seule pour les
/// spectateurs qui ne sont ni admin ni coach de la saison.
class MatchLiveTab extends ConsumerWidget {
  const MatchLiveTab({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEditAsync = ref.watch(isMatchCoachOrAdminProvider(matchId));
    final stateAsync = ref.watch(matchLiveStateProvider(matchId));

    return stateAsync.when(
      loading: () => const Center(
        child: GrintaLoader.page(
          message: 'Le Tableau Blanc se prépare…',
          semanticLabel: 'Chargement du Tableau Blanc',
        ),
      ),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(humanizeError(error), textAlign: TextAlign.center),
        ),
      ),
      data: (bundle) {
        final canEdit = canEditAsync.valueOrNull ?? false;

        if (!bundle.session.sessionExists) {
          if (!canEdit) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Le match n’a pas encore démarré.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return MatchLivePreKickoffPage(
            matchId: matchId,
            bundle: bundle,
            canEdit: true,
          );
        }

        if (bundle.session.state == MatchLiveState.notStarted) {
          return MatchLivePreKickoffPage(
            matchId: matchId,
            bundle: bundle,
            canEdit: canEdit,
          );
        }

        return MatchLiveRunningPage(
          matchId: matchId,
          bundle: bundle,
          canEdit: canEdit,
        );
      },
    );
  }
}
