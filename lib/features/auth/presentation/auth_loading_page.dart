import 'dart:async';

import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthLoadingPage extends ConsumerStatefulWidget {
  const AuthLoadingPage({super.key});

  @override
  ConsumerState<AuthLoadingPage> createState() => _AuthLoadingPageState();
}

class _AuthLoadingPageState extends ConsumerState<AuthLoadingPage> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final profile = ref.read(authControllerProvider).profile;
      if (profile?.isPending == true) {
        unawaited(ref.read(authControllerProvider.notifier).refreshProfile());
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    if (auth.profile?.isPending != true) {
      return const Scaffold(
        body: Center(
          child: GrintaLoader.page(
            message: 'Préparation de ton espace…',
            semanticLabel: 'Préparation de ton espace',
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.hourglass_top_rounded, size: 58),
                  const SizedBox(height: 20),
                  Text(
                    'Compte en attente de validation',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Un responsable doit encore accepter ton inscription. '
                    'Cette page se met à jour automatiquement dès que ton '
                    'compte est validé.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: auth.isLoading
                        ? null
                        : () => ref
                              .read(authControllerProvider.notifier)
                              .refreshProfile(),
                    icon: auth.isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: GrintaProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: const Text('Vérifier maintenant'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: auth.isLoading
                        ? null
                        : () => ref
                              .read(authControllerProvider.notifier)
                              .signOut(),
                    child: const Text('Se déconnecter'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
