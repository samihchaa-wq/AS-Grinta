import 'dart:async';

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

    Future<void> select(LiveViewMode next) async {
      final modeNotifier = ref.read(liveViewModeProvider(matchId).notifier);
      final controller = ref.read(matchLiveStateProvider(matchId).notifier);

      if (next == LiveViewMode.spectator) {
        modeNotifier.state = LiveViewMode.spectator;
        if (pilot == LivePilot.me) await controller.releasePilot();
        return;
      }

      try {
        // Le serveur prend la décision. Si la place est occupée, le snapshot
        // revient avec pilot=other et l'écran propose alors « Prendre la main ».
        await controller.claimPilot(
          plannedDurationMinutes: bundle.session.planPlannedDurationMinutes,
        );
        modeNotifier.state = LiveViewMode.pilot;
      } catch (_) {
        // Le contrôleur a déjà affiché un message propre et relu le serveur.
      }
    }

    final started = bundle.session.sessionExists &&
        bundle.session.state != MatchLiveState.notStarted;
    final Widget body;
    if (mode == LiveViewMode.spectator) {
      body = _spectatorView(bundle);
    } else {
      body = switch (pilot) {
        LivePilot.me => _PilotSession(
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
          ),
        LivePilot.other => _SomeoneElsePilots(matchId: matchId),
        LivePilot.nobody => _PilotPlaceAvailable(matchId: matchId),
      };
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
            onSelectionChanged: (selection) {
              unawaited(select(selection.first));
            },
          ),
        ),
        body,
      ],
    );
  }
}

/// La place a expiré (par exemple après une coupure réseau d'une minute) et
/// personne ne l'a reprise. Un clic suffit pour redevenir pilote.
class _PilotPlaceAvailable extends ConsumerWidget {
  const _PilotPlaceAvailable({required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
      child: Column(
        children: [
          const Text(
            'Personne ne pilote le Live',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              try {
                await ref
                    .read(matchLiveStateProvider(matchId).notifier)
                    .claimPilot();
              } catch (_) {}
            },
            child: const Text('Piloter le Live'),
          ),
        ],
      ),
    );
  }
}

/// Onglet « Piloter » alors qu'un autre téléphone pilote.
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
            'Quelqu’un d’autre pilote déjà le Live',
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
              if (confirmed != true) return;
              try {
                await ref
                    .read(matchLiveStateProvider(matchId).notifier)
                    .takeOverPilot();
              } catch (_) {}
            },
            child: const Text('Prendre la main'),
          ),
        ],
      ),
    );
  }
}

/// Tant qu'elle est affichée, la vue pilote envoie un signe de vie toutes les
/// 15 secondes. Quitter l'écran ou mettre l'application en arrière-plan libère
/// immédiatement la place ; une coupure réseau est couverte par l'expiration
/// serveur d'environ une minute.
class _PilotSession extends ConsumerStatefulWidget {
  const _PilotSession({required this.matchId, required this.child});

  final String matchId;
  final Widget child;

  @override
  ConsumerState<_PilotSession> createState() => _PilotSessionState();
}

class _PilotSessionState extends ConsumerState<_PilotSession>
    with WidgetsBindingObserver {
  Timer? _heartbeatTimer;
  late final MatchLiveStateController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(matchLiveStateProvider(widget.matchId).notifier);
    WidgetsBinding.instance.addObserver(this);
    _heartbeatTimer = Timer.periodic(
      matchLivePilotHeartbeatInterval,
      (_) => unawaited(_controller.heartbeatPilot()),
    );
  }

  void _releaseForBackground() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    ref.read(liveViewModeProvider(widget.matchId).notifier).state =
        LiveViewMode.spectator;
    unawaited(_controller.releasePilot());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _releaseForBackground();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    unawaited(_controller.releasePilot());
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
