import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _avatarController;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(authControllerProvider).profile;
    _firstNameController = TextEditingController(text: profile?.firstName ?? '');
    _lastNameController = TextEditingController(text: profile?.lastName ?? '');
    _avatarController = TextEditingController(text: profile?.avatarPath ?? '');
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _avatarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final profile = authState.profile;

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile?.fullName.isNotEmpty == true ? profile!.fullName : 'Profil utilisateur',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text('Rôle : ${profile?.role.label ?? 'inconnu'}'),
                  Text('Statut : ${profile?.isActive == true ? 'Actif' : 'Inactif'}'),
                  Text('Gardien : ${profile?.isGoalkeeper == true ? 'Oui' : 'Non'}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _firstNameController,
            decoration: const InputDecoration(labelText: 'Prénom'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _lastNameController,
            decoration: const InputDecoration(labelText: 'Nom'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _avatarController,
            decoration: const InputDecoration(labelText: 'Photo (URL ou chemin)'),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: authState.isLoading
                ? null
                : () async {
                    await ref.read(authControllerProvider.notifier).updateProfile(
                          firstName: _firstNameController.text.trim(),
                          lastName: _lastNameController.text.trim(),
                          avatarPath: _avatarController.text.trim(),
                        );
                  },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Enregistrer'),
          ),
          if (profile?.role == AuthRole.admin) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: const Text('Administration'),
            ),
          ],
        ],
      ),
    );
  }
}
