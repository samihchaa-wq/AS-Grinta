import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/match_live/domain/match_live_session.dart';
import 'package:as_grinta/features/match_live/domain/match_live_state_bundle.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_pilot.dart';
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
    ref.listen<String?>(matchLiveActionMessageProvider(matchId), (
      previous,
      next,
    ) {
      if (next == null || next == previous) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(next)));
      ref.read(matchLiveActionMessageProvider(matchId).notifier).state = null;
    });

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
          // De T-15 jusqu'à la fin du match : une seule personne pilote
          // (préparation puis direct), tous les autres suivent en spectateur.
          // Un coach choisit sous « Live » ; un joueur est spectateur.
          if (bundle.session.state != MatchLiveState.finished) {
            final Widget child = canEdit
                ? _CoachLiveView(matchId: matchId, bundle: bundle)
                : _spectatorView(bundle);
            return _LiveRealtimeBoundary(matchId: matchId, child: child);
          }

          final page = MatchLiveRunningPage(
            matchId: matchId,
            bundle: bundle,
            canEdit: canEdit,
          );
          if (!canEdit) return page;
          return _LiveRealtimeBoundary(matchId: matchId, child: page);
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

/// Vue spectateur : composition prévue avant le coup d'envoi, direct ensuite.
Widget _spectatorView(MatchLiveStateBundle bundle) {
  final session = bundle.session;
  if (session.sessionExists && session.state != MatchLiveState.notStarted) {
    return MatchLiveSpectatorView(bundle: bundle);
  }
  return MatchLivePreKickoffSpectatorView(bundle: bundle);
}

/// Coach de T-15 à la fin du match : barre « Spectateur | Piloter ».
class _CoachLiveView extends ConsumerWidget {
  const _CoachLiveView({required this.matchId, required this.bundle});

  final String matchId;
  final MatchLiveStateBundle bundle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(liveViewModeProvider(matchId));
    final pilot = ref.watch(livePilotProvider(matchId));

    void select(LiveViewMode next) {
      ref.read(liveViewModeProvider(matchId).notifier).state = next;
      final pilotNotifier = ref.read(livePilotProvider(matchId).notifier);
      if (next == LiveViewMode.pilot &&
          pilotNotifier.state == LivePilot.nobody) {
        pilotNotifier.state = LivePilot.me;
      } else if (next == LiveViewMode.spectator &&
          pilotNotifier.state == LivePilot.me) {
        pilotNotifier.state = LivePilot.nobody;
      }
    }

    final started = bundle.session.sessionExists &&
        bundle.session.state != MatchLiveState.notStarted;
    final Widget body;
    if (mode == LiveViewMode.spectator) {
      body = _spectatorView(bundle);
    } else if (pilot == LivePilot.me) {
      // Même session de pilote avant et après le coup d'envoi : le pilote de
      // la préparation reste pilote du direct.
      body = _PilotSession(
        matchId: matchId,
        child: started
            ? MatchLiveRunningPage(
                matchId: matchId,
                bundle: bundle,
                canEdit: true,
                fullScreen: true,
              )
            : MatchLivePreKickoffPage(
                matchId: matchId,
                bundle: bundle,
                canEdit: true,
              ),
      );
    } else {
      body = _SomeoneElsePilots(matchId: matchId);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: SegmentedButton<LiveViewMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: LiveViewMode.spectator,
                label: Text('Spectateur'),
              ),
              ButtonSegment(
                value: LiveViewMode.pilot,
                label: Text('Piloter'),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (selection) => select(selection.first),
          ),
        ),
        body,
      ],
    );
  }
}

/// Onglet « Piloter » alors qu'un autre coach pilote.
class _SomeoneElsePilots extends ConsumerWidget {
  const _SomeoneElsePilots({required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
      child: Column(
        children: [
          Text(
            'Quelqu’un d’autre pilote déjà le live',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Prendre la main ?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Annuler'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Prendre la main'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                ref.read(livePilotProvider(matchId).notifier).state =
                    LivePilot.me;
              }
            },
            child: const Text('Prendre la main'),
          ),
        ],
      ),
    );
  }
}

/// Tant qu'elle est affichée, la vue pilote tient la place de pilote ; quitter
/// l'onglet Live ou la fiche du match la libère.
class _PilotSession extends ConsumerStatefulWidget {
  const _PilotSession({required this.matchId, required this.child});

  final String matchId;
  final Widget child;

  @override
  ConsumerState<_PilotSession> createState() => _PilotSessionState();
}

class _PilotSessionState extends ConsumerState<_PilotSession> {
  late final StateController<LivePilot> _pilot =
      ref.read(livePilotProvider(widget.matchId).notifier);

  @override
  void initState() {
    super.initState();
    _pilot; // Lu tout de suite : `ref` n'est plus utilisable au démontage.
  }

  @override
  void dispose() {
    final pilot = _pilot;
    // Différé : on ne modifie pas l'état pendant le démontage de l'écran.
    Future.microtask(() {
      // L'état n'existe plus si l'application entière se ferme.
      if (pilot.mounted && pilot.state == LivePilot.me) {
        pilot.state = LivePilot.nobody;
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _LiveRealtimeBoundary extends ConsumerWidget {
  const _LiveRealtimeBoundary({required this.matchId, required this.child});

  final String matchId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final realtimeDegraded = ref.watch(
      matchLiveRealtimeDegradedProvider(matchId),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (realtimeDegraded)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 12, 2),
            child: _RealtimeFallbackNotice(),
          ),
        child,
      ],
    );
  }
}

class _RealtimeFallbackNotice extends StatelessWidget {
  const _RealtimeFallbackNotice();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      label:
          'Connexion temps réel interrompue. Synchronisation de secours active.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.sync_problem_rounded, color: colors.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Temps réel interrompu. Synchronisation de secours active.',
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
