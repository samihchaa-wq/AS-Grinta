import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  String? _localError;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(authControllerProvider).profile;
    _firstNameController =
        TextEditingController(text: profile?.firstName ?? '');
    _lastNameController = TextEditingController(text: profile?.lastName ?? '');
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final profile = authState.profile;
    final busy = authState.isLoading;

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
                    profile?.fullName.isNotEmpty == true
                        ? profile!.fullName
                        : 'Profil utilisateur',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  if ((profile?.username ?? '').isNotEmpty)
                    Text('Identifiant : ${profile!.username!}'),
                  Text('Rôle : ${profile?.role.label ?? 'inconnu'}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _firstNameController,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Prénom'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _lastNameController,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nom'),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: busy ? null : _saveProfile,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Enregistrer'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : () => _changePassword(context),
            icon: const Icon(Icons.lock_reset_outlined),
            label: const Text('Changer le mot de passe'),
          ),
          if (_localError != null || authState.error != null) ...[
            const SizedBox(height: 12),
            Text(
              _localError ?? authState.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (profile?.role.isStaff == true) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => context.push('/admin'),
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: const Text('Administration'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    if (firstName.isEmpty || lastName.isEmpty) {
      setState(() => _localError = 'Le prénom et le nom sont obligatoires.');
      return;
    }
    setState(() => _localError = null);
    await ref.read(authControllerProvider.notifier).updateProfile(
          firstName: firstName,
          lastName: lastName,
        );
    if (!mounted) return;
    if (ref.read(authControllerProvider).error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil enregistré.')),
      );
    }
  }

  Future<void> _changePassword(BuildContext context) async {
    final passwordController = TextEditingController();
    final confirmationController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Changer le mot de passe'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Nouveau mot de passe'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmationController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirmation'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final password = passwordController.text;
              if (password.length < 8 ||
                  password != confirmationController.text) {
                return;
              }
              Navigator.pop(dialogContext, password);
            },
            child: const Text('Modifier'),
          ),
        ],
      ),
    );
    passwordController.dispose();
    confirmationController.dispose();
    if (result == null || !mounted) return;
    await ref.read(authControllerProvider.notifier).updatePassword(result);
  }
}
