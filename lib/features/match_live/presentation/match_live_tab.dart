import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/match_live/domain/match_live_session.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_pre_kickoff_page.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_running_page.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/match_live_add_player_sheet.dart';
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

        try {
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
            final page = MatchLivePreKickoffPage(
              matchId: matchId,
              bundle: bundle,
              canEdit: canEdit,
            );
            return canEdit
                ? _LiveAddPlayerAction(
                    matchId: matchId,
                    compact: false,
                    child: page,
                  )
                : page;
          }

          final page = MatchLiveRunningPage(
            matchId: matchId,
            bundle: bundle,
            canEdit: canEdit,
          );
          if (!canEdit || bundle.session.state == MatchLiveState.finished) {
            return page;
          }
          return _LiveAddPlayerAction(
            matchId: matchId,
            compact: true,
            child: page,
          );
        } catch (error, stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'match_live',
              context: ErrorDescription('construction du Tableau Blanc'),
            ),
          );
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Impossible d’afficher le Live pour le moment. Réessaie.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
      },
    );
  }
}

class _LiveAddPlayerAction extends ConsumerWidget {
  const _LiveAddPlayerAction({
    required this.matchId,
    required this.compact,
    required this.child,
  });

  final String matchId;
  final bool compact;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = compact
        ? Align(
            alignment: Alignment.centerRight,
            child: SizedBox.square(
              dimension: 34,
              child: IconButton.filledTonal(
                tooltip: 'Ajouter un joueur',
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: () => showMatchLiveAddPlayerSheet(
                  context,
                  ref,
                  matchId: matchId,
                ),
                icon: const Icon(Icons.add_rounded, size: 20),
              ),
            ),
          )
        : SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => showMatchLiveAddPlayerSheet(
                context,
                ref,
                matchId: matchId,
              ),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Ajouter un joueur'),
            ),
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: compact
              ? const EdgeInsets.fromLTRB(12, 4, 12, 0)
              : const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: action,
        ),
        child,
      ],
    );
  }
}
