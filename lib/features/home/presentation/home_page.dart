import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AS Grinta'),
        actions: [
          IconButton(
            tooltip: 'Profil',
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.go('/profile'),
          ),
          IconButton(
            tooltip: 'Déconnexion',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).signOut();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Bienvenue', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            authState.profile?.fullName.isNotEmpty == true
                ? 'Bonjour ${authState.profile!.fullName}'
                : 'Le socle Flutter est prêt.',
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Profil actif'),
                  const SizedBox(height: 8),
                  Text('Rôle : ${authState.profile?.role.label ?? 'inconnu'}'),
                  Text(
                    'Gardien : ${authState.profile?.isGoalkeeper == true ? 'Oui' : 'Non'}',
                  ),
                  if (authState.profile?.role == AuthRole.admin) ...[
                    const SizedBox(height: 8),
                    const Text('Vous disposez des droits d’administration.'),
                  ] else if (authState.profile?.role == AuthRole.moderateur) ...[
                    const SizedBox(height: 8),
                    const Text('Vous disposez des droits de modération.'),
                  ] else ...[
                    const SizedBox(height: 8),
                    const Text('Vous êtes un pronostiqueur standard.'),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
