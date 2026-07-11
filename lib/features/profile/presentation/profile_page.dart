import 'dart:typed_data';

import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _nicknameController;
  Uint8List? _pendingAvatarBytes;
  String? _avatarUrl;
  bool _isUploadingAvatar = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(authControllerProvider).profile;
    _firstNameController =
        TextEditingController(text: profile?.firstName ?? '');
    _lastNameController = TextEditingController(text: profile?.lastName ?? '');
    _nicknameController = TextEditingController(text: profile?.surnom ?? '');
    _avatarUrl = profile?.avatarPath;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  ImageProvider<Object>? _avatarProvider() {
    final pending = _pendingAvatarBytes;
    if (pending != null) return MemoryImage(pending);
    final url = _avatarUrl;
    if (url != null && url.isNotEmpty) return NetworkImage(url);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final profile = authState.profile;
    final busy = authState.isLoading || _isUploadingAvatar;
    final avatarProvider = _avatarProvider();

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 54,
                  backgroundImage: avatarProvider,
                  child: avatarProvider == null
                      ? const Icon(Icons.person, size: 54)
                      : null,
                ),
                IconButton.filled(
                  tooltip: 'Choisir une photo',
                  onPressed: busy ? null : _pickAvatar,
                  icon: const Icon(Icons.photo_camera_outlined),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
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
                  if (profile != null &&
                      profile.displayName != profile.fullName) ...[
                    const SizedBox(height: 4),
                    Text('Nom affiché : ${profile.displayName}'),
                  ],
                  const SizedBox(height: 8),
                  if ((profile?.email ?? '').isNotEmpty)
                    Text('Identifiant : ${profile!.email!}'),
                  Text('Rôle : ${profile?.role.label ?? 'inconnu'}'),
                  Text(
                    'Statut : ${profile?.isActive == true ? 'Actif' : 'Inactif'}',
                  ),
                  Text(
                    'Gardien : ${profile?.isGoalkeeper == true ? 'Oui' : 'Non'}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nicknameController,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Surnom (facultatif)',
              helperText:
                  'Affiché partout dans l’application. Sinon, seul le prénom apparaît.',
            ),
          ),
          const SizedBox(height: 16),
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

  Future<void> _pickAvatar() async {
    setState(() => _localError = null);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      if (picked == null) return;

      final original = await picked.readAsBytes();
      final decoded = img.decodeImage(original);
      if (decoded == null) {
        throw StateError('Le format de cette image n’est pas pris en charge.');
      }

      final resized = decoded.width > 1024 || decoded.height > 1024
          ? img.copyResize(
              decoded,
              width: decoded.width >= decoded.height ? 1024 : null,
              height: decoded.height > decoded.width ? 1024 : null,
              interpolation: img.Interpolation.average,
            )
          : decoded;
      final compressed = Uint8List.fromList(
        img.encodeJpg(resized, quality: 82),
      );
      if (!mounted) return;
      setState(() => _pendingAvatarBytes = compressed);
    } catch (_) {
      if (mounted) {
        setState(() => _localError = 'La photo n’a pas pu être préparée.');
      }
    }
  }

  Future<void> _saveProfile() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    if (firstName.isEmpty || lastName.isEmpty) {
      setState(() => _localError = 'Le prénom et le nom sont obligatoires.');
      return;
    }

    setState(() {
      _isUploadingAvatar = true;
      _localError = null;
    });
    try {
      var avatarUrl = _avatarUrl ?? '';
      if (_pendingAvatarBytes != null) {
        avatarUrl = await ref
            .read(authRepositoryProvider)
            .uploadAvatar(_pendingAvatarBytes!);
      }
      await ref.read(authControllerProvider.notifier).updateProfile(
            firstName: firstName,
            lastName: lastName,
            surnom: _nicknameController.text,
            avatarPath: avatarUrl,
          );
      if (!mounted) return;
      setState(() {
        _avatarUrl = avatarUrl;
        _pendingAvatarBytes = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil enregistré.')),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _localError = 'Le profil n’a pas pu être enregistré.');
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
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
