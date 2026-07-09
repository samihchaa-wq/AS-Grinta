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
    Future.microtask(() => ref.read(liveControllerProvider.notifier).initialize(widget.matchId));
  }

  @override
  Widget build(BuildContext context) {
    final liveState = ref.watch(liveControllerProvider);
    final authState = ref.watch(authControllerProvider);
    final canControl = authState.profile?.role == AuthRole.admin || authState.profile?.role == AuthRole.moderateur;

    return Scaffold(
      appBar: AppBar(title: const Text('Live Match')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                    Text('Contrôleur : ${liveState.session?.controllerProfileId ?? 'aucun'}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: canControl ? () => ref.read(liveControllerProvider.notifier).start(widget.matchId) : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Démarrer'),
                ),
                FilledButton.icon(
                  onPressed: canControl ? () => ref.read(liveControllerProvider.notifier).pause(widget.matchId) : null,
                  icon: const Icon(Icons.pause),
                  label: const Text('Pause'),
                ),
                FilledButton.icon(
                  onPressed: canControl ? () => ref.read(liveControllerProvider.notifier).setHalftime(widget.matchId) : null,
                  icon: const Icon(Icons.timelapse),
                  label: const Text('Mi-temps'),
                ),
                FilledButton.icon(
                  onPressed: canControl ? () => ref.read(liveControllerProvider.notifier).finish(widget.matchId) : null,
                  icon: const Icon(Icons.flag),
                  label: const Text('Fin'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: canControl ? () => ref.read(liveControllerProvider.notifier).claimControl(widget.matchId) : null,
              icon: const Icon(Icons.control_point),
              label: const Text('Prendre le contrôle'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => context.go('/live/${widget.matchId}/gameplay'),
              icon: const Icon(Icons.sports_soccer),
              label: const Text('Composition & déroulé'),
            ),
          ],
        ),
      ),
    );
  }
}
