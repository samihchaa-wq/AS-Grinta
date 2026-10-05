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
/// l'état de la session live. Pendant le match, le coach de la saison arrive
/// directement en pilotage ; tous les autres, administrateurs compris, arrivent
/// directement en spectateur.
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
    final isCoachAsync = ref.watch(isMatchLiveCoachProvider(matchId));
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
        final isCoach = isCoachAsync.valueOrNull ?? false;

        try {
          if (bundle.session.state != MatchLiveState.finished) {
            final Widget child = isCoach
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

/// Coach de T-15 à la fin du match : directement en pilotage, sans passer par
/// une vue spectateur. La place est demandée au serveur à l'ouverture et au
/// retour au premier plan ; si un autre téléphone du coach la tient encore,
/// l'écran propose « Prendre la main ».
class _CoachLiveView extends ConsumerStatefulWidget {
  const _CoachLiveView({required this.matchId, required this.bundle});

  final String matchId;
  final MatchLiveStateBundle bundle;

  @override
  ConsumerState<_CoachLiveView> createState() => _CoachLiveViewState();
}

class _CoachLiveViewState extends ConsumerState<_CoachLiveView>
    with WidgetsBindingObserver {
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_claim()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Passer en arrière-plan libère la place (voir _PilotSession) : au retour,
    // le coach la reprend sans rien toucher.
    if (state == AppLifecycleState.resumed) unawaited(_claim());
  }

  Future<void> _claim() async {
    if (!mounted || _claiming) return;
    if (ref.read(livePilotProvider(widget.matchId)) != LivePilot.nobody) {
      return;
    }
    setState(() => _claiming = true);
    try {
      // Le serveur prend la décision. Si la place est occupée, le snapshot
      // revient avec pilot=other et l'écran propose alors « Prendre la main ».
      await ref
          .read(matchLiveStateProvider(widget.matchId).notifier)
          .claimPilot(
            plannedDurationMinutes:
                widget.bundle.session.planPlannedDurationMinutes,
          );
    } catch (_) {
      // Le contrôleur a déjà affiché un message propre et relu le serveur.
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matchId = widget.matchId;
    final bundle = widget.bundle;
    final pilot = ref.watch(livePilotProvider(matchId));
    final started = bundle.session.sessionExists &&
        bundle.session.state != MatchLiveState.notStarted;

    return switch (pilot) {
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
      LivePilot.nobody when _claiming => const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: GrintaLoader.page(
              message: 'Ouverture du pilotage…',
              semanticLabel: 'Ouverture du pilotage du Live',
            ),
          ),
        ),
      LivePilot.nobody => _PilotPlaceAvailable(onClaim: _claim),
    };
  }
}

/// La place n'a pas pu être prise automatiquement (par exemple sans réseau)
/// ou a expiré après une coupure d'une minute. Un clic suffit pour la reprendre.
class _PilotPlaceAvailable extends StatelessWidget {
  const _PilotPlaceAvailable({required this.onClaim});

  final Future<void> Function() onClaim;

  @override
  Widget build(BuildContext context) {
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
            onPressed: () => unawaited(onClaim()),
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
