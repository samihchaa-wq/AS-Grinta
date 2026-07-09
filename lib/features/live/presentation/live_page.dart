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

class _LivePageState extends ConsumerState<LivePage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(liveControllerProvider.notifier).initialize(widget.matchId),
    );
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
    final ownsControl = isAdmin &&
        localSessionId != null &&
        liveState.session?.controllerProfileId == userId &&
        liveState.session?.controllerSessionId == localSessionId;
    final canClaim = isAdmin && liveState.session?.controllerProfileId == null;

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
                  Text('Temps : ${liveState.session?.elapsedSeconds ?? 0}s'),
                  const SizedBox(height: 8),
                  Text(
                    'Contrôleur : '
                    '${liveState.session?.controllerProfileId ?? 'aucun'}',
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
          if (isAdmin) ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: ownsControl
                      ? () => ref
                          .read(liveControllerProvider.notifier)
                          .start(widget.matchId)
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Démarrer'),
                ),
                FilledButton.icon(
                  onPressed: ownsControl
                      ? () => ref
                          .read(liveControllerProvider.notifier)
                          .pause(widget.matchId)
                      : null,
                  icon: const Icon(Icons.pause),
                  label: const Text('Pause'),
                ),
                FilledButton.icon(
                  onPressed: ownsControl
                      ? () => ref
                          .read(liveControllerProvider.notifier)
                          .setHalftime(widget.matchId)
                      : null,
                  icon: const Icon(Icons.timelapse),
                  label: const Text('Mi-temps'),
                ),
                FilledButton.icon(
                  onPressed: ownsControl
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
              onPressed: ownsControl
                  ? () => ref
                      .read(liveControllerProvider.notifier)
                      .releaseControl(widget.matchId)
                  : null,
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Céder volontairement le contrôle'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: ownsControl
                  ? () => context.go('/live/${widget.matchId}/gameplay')
                  : null,
              icon: const Icon(Icons.sports_soccer),
              label: const Text('Composition & déroulé'),
            ),
          ],
          if (isModerator) ...[
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Le Modérateur ne peut pas contrôler normalement le Live. '
                  'La reprise forcée n’est disponible qu’après 60 secondes de déconnexion du contrôleur.',
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
