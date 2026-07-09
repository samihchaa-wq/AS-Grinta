import 'dart:async';

import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/live/presentation/live_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class LivePage extends ConsumerStatefulWidget {
  const LivePage({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<LivePage> createState() => _LivePageState();
}

class _LivePageState extends ConsumerState<LivePage>
    with WidgetsBindingObserver {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    Future.microtask(
      () => ref.read(liveControllerProvider.notifier).initialize(widget.matchId),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(
        ref.read(liveControllerProvider.notifier).markDisconnected(widget.matchId),
      );
    } else if (state == AppLifecycleState.resumed) {
      unawaited(
        ref.read(liveControllerProvider.notifier).markReconnected(widget.matchId),
      );
    }
  }

  @override
  void dispose() {
    unawaited(
      ref.read(liveControllerProvider.notifier).markDisconnected(widget.matchId),
    );
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  int _displayedSeconds() {
    final session = ref.read(liveControllerProvider).session;
    if (session == null) return 0;
    var seconds = session.elapsedSeconds;
    if (session.status == 'running' && session.clockStartedAt != null) {
      final runningSeconds = DateTime.now()
          .toUtc()
          .difference(session.clockStartedAt!.toUtc())
          .inSeconds
          .clamp(0, 86400)
          .toInt();
      seconds += runningSeconds;
    }
    return seconds;
  }

  String _formatClock(int seconds) {
    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remaining.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final liveState = ref.watch(liveControllerProvider);
    final authState = ref.watch(authControllerProvider);
    final localSessionId = ref.watch(liveControlSessionIdProvider);
    final role = authState.profile?.role;
    final userId = authState.profile?.id;
    final isAdmin = role == AuthRole.admin;
    final isModerator = role == AuthRole.moderateur;
    final ownsControl = localSessionId != null &&
        liveState.session?.controllerProfileId == userId;
    final canClaim = isAdmin && liveState.session?.controllerProfileId == null;
    final canOperate = ownsControl && (isAdmin || isModerator);

    return Scaffold(
      appBar: AppBar(title: const Text('Live Match')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('État : ${liveState.session?.status ?? 'not_started'}'),
                  const SizedBox(height: 8),
                  Text(
                    'Temps : ${_formatClock(_displayedSeconds())}',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    liveState.session?.controllerProfileId == null
                        ? 'Contrôleur : aucun'
                        : ownsControl
                            ? 'Contrôleur : cette connexion'
                            : 'Contrôleur : une autre connexion',
                  ),
                ],
              ),
            ),
          ),
          if (liveState.error != null) ...[
            const SizedBox(height: 12),
            Text(
              liveState.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          if (isAdmin || (isModerator && ownsControl)) ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: canOperate
                      ? () => ref
                          .read(liveControllerProvider.notifier)
                          .start(widget.matchId)
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Démarrer'),
                ),
                FilledButton.icon(
                  onPressed: canOperate
                      ? () => ref
                          .read(liveControllerProvider.notifier)
                          .pause(widget.matchId)
                      : null,
                  icon: const Icon(Icons.pause),
                  label: const Text('Pause'),
                ),
                FilledButton.icon(
                  onPressed: canOperate
                      ? () => ref
                          .read(liveControllerProvider.notifier)
                          .setHalftime(widget.matchId)
                      : null,
                  icon: const Icon(Icons.timelapse),
                  label: const Text('Mi-temps'),
                ),
                FilledButton.icon(
                  onPressed: canOperate
                      ? () => ref
                          .read(liveControllerProvider.notifier)
                          .finish(widget.matchId)
                      : null,
                  icon: const Icon(Icons.flag),
                  label: const Text('Fin'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (isAdmin)
              OutlinedButton.icon(
                onPressed: canClaim
                    ? () => ref
                        .read(liveControllerProvider.notifier)
                        .claimControl(widget.matchId)
                    : null,
                icon: const Icon(Icons.control_point),
                label: const Text('Prendre le contrôle'),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: canOperate
                  ? () => ref
                      .read(liveControllerProvider.notifier)
                      .releaseControl(widget.matchId)
                  : null,
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Céder volontairement le contrôle'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: canOperate
                  ? () => context.go('/live/${widget.matchId}/gameplay')
                  : null,
              icon: const Icon(Icons.sports_soccer),
              label: const Text('Composition & déroulé'),
            ),
          ],
          if (isModerator && !ownsControl) ...[
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'La reprise forcée devient disponible 60 secondes après la '
                  'déconnexion signalée de la connexion contrôlant le Live.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => ref
                  .read(liveControllerProvider.notifier)
                  .forceResumeControl(widget.matchId),
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: const Text('Reprise forcée après délai de grâce'),
            ),
          ],
        ],
      ),
    );
  }
}
